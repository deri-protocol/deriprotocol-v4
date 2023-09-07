// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@aave/core-v3/contracts/misc/interfaces/IWETH.sol';
import '../../oracle/IOracle.sol';
import '../../utils/Admin.sol';
import '../../library/SafeMath.sol';

/**
 * @title UniswapV3 Swapper Contract
 * @dev This contract utilizes the Uniswap V3 protocol for swapping tokens.
 */
contract UniswapV3 is Admin {

    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SafeMath for int256;

    uint256 constant UONE = 1e18;

    IUniswapV3Factory public immutable factory;

    ISwapRouter public immutable router;

    IOracle public immutable oracle;

    address public immutable tokenB0;

    address public immutable tokenWETH;

    uint24  public immutable feeB0WETH;

    uint8   public immutable decimalsB0;

    uint256 public immutable maxSlippageRatio;

    // fromToken => toToken => path
    mapping (address => mapping (address => bytes)) public paths;

    // tokenBX => oracle symbolId
    mapping (address => bytes32) public oracleIds;

    constructor (
        address factory_,
        address router_,
        address oracle_,
        address tokenB0_,
        address tokenWETH_,
        uint24  feeB0WETH_,
        uint256 maxSlippageRatio_,
        string memory nativePriceSymbol // BNBUSD for BSC, ETHUSD for Ethereum
    ) {
        factory = IUniswapV3Factory(factory_);
        router = ISwapRouter(router_);
        oracle = IOracle(oracle_);
        tokenB0 = tokenB0_;
        tokenWETH = tokenWETH_;
        feeB0WETH = feeB0WETH_;
        decimalsB0 = IERC20Metadata(tokenB0_).decimals();
        maxSlippageRatio = maxSlippageRatio_;

        require(
            factory.getPool(tokenB0_, tokenWETH_, feeB0WETH_) != address(0),
            'Swapper: no native path'
        );

        paths[tokenB0_][tokenWETH_] = abi.encodePacked(tokenB0_, feeB0WETH_, tokenWETH_);
        paths[tokenWETH_][tokenB0_] = abi.encodePacked(tokenWETH_, feeB0WETH_, tokenB0_);

        bytes32 symbolId = keccak256(abi.encodePacked(nativePriceSymbol));
        require(oracle.getValue(symbolId) != 0, 'Swapper.constructor: no native price');
        oracleIds[tokenWETH_] = symbolId;

        IERC20(tokenB0_).safeApprove(router_, type(uint256).max);
    }

    // A complete path is constructed as
    // [tokenB0, fees[0], tokens[0], fees[1], tokens[1] ... ]
    function setPath(string memory priceSymbol, uint24[] calldata fees, address[] calldata tokens) external _onlyAdmin_ {
        uint256 length = fees.length;

        require(length >= 1, 'Swapper.setPath: invalid path length');
        require(tokens.length == length, 'Swapper.setPath: invalid paired path');

        address tokenBX = tokens[length - 1];
        bytes memory path;
        address input;

        // Forward path
        input = tokenB0;
        path = abi.encodePacked(input);
        for (uint256 i = 0; i < length; i++) {
            require(
                factory.getPool(input, tokens[i], fees[i]) != address(0),
                'Swapper.setPath: path broken'
            );
            path = abi.encodePacked(path, fees[i], tokens[i]);
            input = tokens[i];
        }
        paths[tokenB0][tokenBX] = path;

        // Backward path
        input = tokenBX;
        path = abi.encodePacked(input);
        for (uint256 i = length - 1; i > 0; i--) {
            path = abi.encodePacked(path, fees[i], tokens[i - 1]);
            input = tokens[i - 1];
        }
        path = abi.encodePacked(path, fees[0], tokenB0);
        paths[tokenBX][tokenB0] = path;

        bytes32 symbolId = keccak256(abi.encodePacked(priceSymbol));
        require(oracle.getValue(symbolId) != 0, 'Swapper.setPath: no price');
        oracleIds[tokenBX] = symbolId;

        IERC20(tokenBX).safeApprove(address(router), type(uint256).max);
    }

    function getPath(address tokenBX) external view returns (bytes memory) {
        return paths[tokenB0][tokenBX];
    }

    function isSupportedToken(address tokenBX) external view returns (bool) {
        if (tokenBX == tokenB0) return true;
        bytes storage path1 = paths[tokenB0][tokenBX];
        bytes storage path2 = paths[tokenBX][tokenB0];
        return path1.length != 0 && path2.length != 0;
    }

    function getTokenPrice(address tokenBX) public view returns (uint256) {
        uint256 decimalsBX = IERC20Metadata(tokenBX).decimals();
        return oracle.getValue(oracleIds[tokenBX]).itou() * 10**decimalsB0 / 10**decimalsBX;
    }

    receive() external payable {}

    //================================================================================

    function swapExactB0ForBX(address tokenBX, uint256 amountB0)
    external returns (uint256 resultB0, uint256 resultBX)
    {
        uint256 price = getTokenPrice(tokenBX);
        uint256 minAmountBX = amountB0 * (UONE - maxSlippageRatio) / price;
        (resultB0, resultBX) = _swapExactTokensForTokens(tokenB0, tokenBX, amountB0, minAmountBX);
    }

    function swapExactBXForB0(address tokenBX, uint256 amountBX)
    external returns (uint256 resultB0, uint256 resultBX)
    {
        uint256 price = getTokenPrice(tokenBX);
        uint256 minAmountB0 = amountBX * price / UONE * (UONE - maxSlippageRatio) / UONE;
        (resultBX, resultB0) = _swapExactTokensForTokens(tokenBX, tokenB0, amountBX, minAmountB0);
    }

    function swapB0ForExactBX(address tokenBX, uint256 maxAmountB0, uint256 amountBX)
    external returns (uint256 resultB0, uint256 resultBX)
    {
        uint256 price = getTokenPrice(tokenBX);
        uint256 maxB0 = amountBX * price / UONE * (UONE + maxSlippageRatio) / UONE;
        if (maxAmountB0 >= maxB0) {
            (resultB0, resultBX) = _swapTokensForExactTokens(tokenB0, tokenBX, maxB0, amountBX);
        } else {
            uint256 minAmountBX = maxAmountB0 * (UONE - maxSlippageRatio) / price;
            (resultB0, resultBX) = _swapExactTokensForTokens(tokenB0, tokenBX, maxAmountB0, minAmountBX);
        }
    }

    function swapBXForExactB0(address tokenBX, uint256 amountB0, uint256 maxAmountBX)
    external returns (uint256 resultB0, uint256 resultBX)
    {
        uint256 price = getTokenPrice(tokenBX);
        uint256 maxBX = amountB0 * (UONE + maxSlippageRatio) / price;
        if (maxAmountBX >= maxBX) {
            (resultBX, resultB0) = _swapTokensForExactTokens(tokenBX, tokenB0, maxBX, amountB0);
        } else {
            uint256 minAmountB0 = maxAmountBX * price / UONE * (UONE - maxSlippageRatio) / UONE;
            (resultBX, resultB0) = _swapExactTokensForTokens(tokenBX, tokenB0, maxAmountBX, minAmountB0);
        }
    }

    function swapExactB0ForETH(uint256 amountB0)
    external returns (uint256 resultB0, uint256 resultBX)
    {
        uint256 price = getTokenPrice(tokenWETH);
        uint256 minAmountBX = amountB0 * (UONE - maxSlippageRatio) / price;
        (resultB0, resultBX) = _swapExactTokensForTokens(tokenB0, tokenWETH, amountB0, minAmountBX);
    }

    function swapExactETHForB0()
    external payable returns (uint256 resultB0, uint256 resultBX)
    {
        uint256 price = getTokenPrice(tokenWETH);
        uint256 amountBX = msg.value;
        uint256 minAmountB0 = amountBX * price / UONE * (UONE - maxSlippageRatio) / UONE;
        (resultBX, resultB0) = _swapExactTokensForTokens(tokenWETH, tokenB0, amountBX, minAmountB0);
    }

    function swapB0ForExactETH(uint256 maxAmountB0, uint256 amountBX)
    external returns (uint256 resultB0, uint256 resultBX)
    {
        uint256 price = getTokenPrice(tokenWETH);
        uint256 maxB0 = amountBX * price / UONE * (UONE + maxSlippageRatio) / UONE;
        if (maxAmountB0 >= maxB0) {
            (resultB0, resultBX) = _swapTokensForExactTokens(tokenB0, tokenWETH, maxB0, amountBX);
        } else {
            uint256 minAmountBX = maxAmountB0 * (UONE - maxSlippageRatio) / price;
            (resultB0, resultBX) = _swapExactTokensForTokens(tokenB0, tokenWETH, maxAmountB0, minAmountBX);
        }
    }

    function swapETHForExactB0(uint256 amountB0)
    external payable returns (uint256 resultB0, uint256 resultBX)
    {
        uint256 price = getTokenPrice(tokenWETH);
        uint256 maxAmountBX = msg.value;
        uint256 maxBX = amountB0 * (UONE + maxSlippageRatio) / price;
        if (maxAmountBX >= maxBX) {
            (resultBX, resultB0) = _swapTokensForExactTokens(tokenWETH, tokenB0, maxBX, amountB0);
        } else {
            uint256 minAmountB0 = maxAmountBX * price / UONE * (UONE - maxSlippageRatio) / UONE;
            (resultBX, resultB0) = _swapExactTokensForTokens(tokenWETH, tokenB0, maxAmountBX, minAmountB0);
        }
    }

    //================================================================================

    function _swapExactTokensForTokens(address token1, address token2, uint256 amount1, uint256 amount2)
    internal returns (uint256 result1, uint256 result2)
    {
        if (amount1 == 0) return (0, 0);

        if (token1 != tokenWETH) {
            IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);
        }

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: paths[token1][token2],
            recipient: token2 == tokenWETH ? address(this) : msg.sender,
            deadline: block.timestamp,
            amountIn: amount1,
            amountOutMinimum: amount2
        });

        uint256 amountOut = router.exactInput{value: token1 == tokenWETH ? amount1 : 0}(params);

        if (token2 == tokenWETH) {
            IWETH(tokenWETH).withdraw(amountOut);
            _sendETH(msg.sender, amountOut);
        }

        result1 = amount1;
        result2 = amountOut;
    }

    function _swapTokensForExactTokens(address token1, address token2, uint256 amount1, uint256 amount2)
    internal returns (uint256 result1, uint256 result2)
    {
        if (amount1 == 0 || amount2 == 0) {
            if (token1 == tokenWETH) {
                _sendETH(msg.sender, address(this).balance);
            }
            return (0, 0);
        }

        if (token1 != tokenWETH) {
            IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);
        }

        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
            path: paths[token2][token1],
            recipient: token2 == tokenWETH ? address(this) : msg.sender,
            deadline: block.timestamp,
            amountOut: amount2,
            amountInMaximum: amount1
        });

        uint256 amountIn = router.exactOutput{value: token1 == tokenWETH ? amount1 : 0}(params);

        if (token2 == tokenWETH) {
            IWETH(tokenWETH).withdraw(amount2);
            _sendETH(msg.sender, amount2);
        }

        result1 = amountIn;
        result2 = amount2;

        if (token1 == tokenWETH) {
            IRouterComplement(address(router)).refundETH();
            _sendETH(msg.sender, address(this).balance);
        } else {
            IERC20(token1).safeTransfer(msg.sender, IERC20(token1).balanceOf(address(this)));
        }
    }

    function _sendETH(address to, uint256 amount) internal {
        (bool success, ) = payable(to).call{value: amount}('');
        require(success, 'Swapper._sendETH: fail');
    }

}

interface IRouterComplement {
    function refundETH() external;
}
