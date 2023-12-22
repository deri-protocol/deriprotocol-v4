// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '../../oracle/IOracle.sol';
import './IBaseSwapper.sol';
import '../../library/SafeMath.sol';
import './SwapperStorage.sol';

contract SwapperImplementation is SwapperStorage {

    using SafeERC20 for IERC20;
    using SafeMath for int256;

    uint256 constant ONE = 1e18;

    IOracle public immutable oracle;

    address public immutable tokenB0;

    uint8 public immutable decimalsB0;

    address public immutable tokenWETH;

    uint256 public constant defaultMaxSlippageRatio = 1e17; // 0.1

    constructor (address oracle_, address tokenB0_, address tokenWETH_) {
        oracle = IOracle(oracle_);
        tokenB0 = tokenB0_;
        decimalsB0 = IERC20Metadata(tokenB0_).decimals();
        tokenWETH = tokenWETH_;
    }

    function isSupportedToken(address tokenBX) public view returns (bool) {
        if (tokenBX == tokenB0) return true;
        if (tokenBX == address(1)) tokenBX = tokenWETH; // ETH is represented as address(1)
        address baseSwapper = baseSwappers[tokenBX];
        if (baseSwapper != address(0)) {
            return IBaseSwapper(baseSwapper).isSupportedSwap(tokenB0, tokenBX);
        } else {
            return false;
        }
    }

    function setBaseSwapper(address tokenBX, address baseSwapper, string memory priceSymbol) external _onlyAdmin_ {
        require(
            IBaseSwapper(baseSwapper).isSupportedSwap(tokenB0, tokenBX),
            'Unsupported swap'
        );
        baseSwappers[tokenBX] = baseSwapper;

        bytes32 oracleId = keccak256(abi.encodePacked(priceSymbol));
        require(oracle.getValue(oracleId) != 0, 'No oracle');
        oracleIds[tokenBX] = oracleId;
    }

    function setMaxSlippageRatio(address tokenBX, uint256 maxSlippageRatio) external _onlyAdmin_ {
        maxSlippageRatios[tokenBX] = maxSlippageRatio;
    }

    function getTokenPrice(address tokenBX) public view returns (uint256) {
        uint8 decimalsBX = tokenBX == tokenWETH ? 18 : IERC20Metadata(tokenBX).decimals();
        return oracle.getValue(oracleIds[tokenBX]).itou() * 10**decimalsB0 / 10**decimalsBX;
    }

    function getMaxSlippageRatio(address tokenBX) public view returns (uint256) {
        uint256 ratio = maxSlippageRatios[tokenBX];
        return ratio == 0 ? defaultMaxSlippageRatio : ratio;
    }

    //================================================================================

    function swapExactB0ForBX(address tokenBX, uint256 amountB0)
    external returns (uint256 resultB0, uint256 resultBX)
    {
        uint256 price = getTokenPrice(tokenBX);
        uint256 maxSlippageRatio = getMaxSlippageRatio(tokenBX);
        uint256 minAmountBX = amountB0 * (ONE - maxSlippageRatio) / price;
        address swapper = _getBaseSwapper(tokenBX);
        IERC20(tokenB0).safeTransferFrom(msg.sender, swapper, amountB0);
        (resultB0, resultBX) = IBaseSwapper(swapper).swapExactTokensForTokens(
            msg.sender, tokenB0, tokenBX, amountB0, minAmountBX
        );
    }

    function swapExactBXForB0(address tokenBX, uint256 amountBX)
    external returns (uint256 resultB0, uint256 resultBX)
    {
        uint256 price = getTokenPrice(tokenBX);
        uint256 maxSlippageRatio = getMaxSlippageRatio(tokenBX);
        uint256 minAmountB0 = amountBX * price / ONE * (ONE - maxSlippageRatio) / ONE;
        address swapper = _getBaseSwapper(tokenBX);
        IERC20(tokenBX).safeTransferFrom(msg.sender, swapper, amountBX);
        (resultBX, resultB0) = IBaseSwapper(swapper).swapExactTokensForTokens(
            msg.sender, tokenBX, tokenB0, amountBX, minAmountB0
        );
    }

    function swapB0ForExactBX(address tokenBX, uint256 maxAmountB0, uint256 amountBX)
    external returns (uint256 resultB0, uint256 resultBX)
    {
        uint256 price = getTokenPrice(tokenBX);
        uint256 maxSlippageRatio = getMaxSlippageRatio(tokenBX);
        uint256 maxB0 = amountBX * price / ONE * (ONE + maxSlippageRatio) / ONE;
        address swapper = _getBaseSwapper(tokenBX);
        if (maxAmountB0 >= maxB0) {
            IERC20(tokenB0).safeTransferFrom(msg.sender, swapper, maxB0);
            (resultB0, resultBX) = IBaseSwapper(swapper).swapTokensForExactTokens(
                msg.sender, tokenB0, tokenBX, maxB0, amountBX
            );
        } else {
            uint256 minAmountBX = maxAmountB0 * (ONE - maxSlippageRatio) / price;
            IERC20(tokenB0).safeTransferFrom(msg.sender, swapper, maxAmountB0);
            (resultB0, resultBX) = IBaseSwapper(swapper).swapExactTokensForTokens(
                msg.sender, tokenB0, tokenBX, maxAmountB0, minAmountBX
            );
        }
    }

    function swapBXForExactB0(address tokenBX, uint256 amountB0, uint256 maxAmountBX)
    external returns (uint256 resultB0, uint256 resultBX)
    {
        uint256 price = getTokenPrice(tokenBX);
        uint256 maxSlippageRatio = getMaxSlippageRatio(tokenBX);
        uint256 maxBX = amountB0 * (ONE + maxSlippageRatio) / price;
        address swapper = _getBaseSwapper(tokenBX);
        if (maxAmountBX >= maxBX) {
            IERC20(tokenBX).safeTransferFrom(msg.sender, swapper, maxBX);
            (resultBX, resultB0) = IBaseSwapper(swapper).swapTokensForExactTokens(
                msg.sender, tokenBX, tokenB0, maxBX, amountB0
            );
        } else {
            uint256 minAmountB0 = maxAmountBX * price / ONE * (ONE - maxSlippageRatio) / ONE;
            IERC20(tokenBX).safeTransferFrom(msg.sender, swapper, maxAmountBX);
            (resultBX, resultB0) = IBaseSwapper(swapper).swapExactTokensForTokens(
                msg.sender, tokenBX, tokenB0, maxAmountBX, minAmountB0
            );
        }
    }

    function swapExactB0ForETH(uint256 amountB0)
    external returns (uint256 resultB0, uint256 resultBX)
    {
        uint256 price = getTokenPrice(tokenWETH);
        uint256 maxSlippageRatio = getMaxSlippageRatio(tokenWETH);
        uint256 minAmountBX = amountB0 * (ONE - maxSlippageRatio) / price;
        address swapper = _getBaseSwapper(tokenWETH);
        IERC20(tokenB0).safeTransferFrom(msg.sender, swapper, amountB0);
        (resultB0, resultBX) = IBaseSwapper(swapper).swapExactTokensForTokens(
            msg.sender, tokenB0, tokenWETH, amountB0, minAmountBX
        );
    }

    function swapExactETHForB0()
    external payable returns (uint256 resultB0, uint256 resultBX)
    {
        uint256 price = getTokenPrice(tokenWETH);
        uint256 maxSlippageRatio = getMaxSlippageRatio(tokenWETH);
        uint256 amountBX = msg.value;
        uint256 minAmountB0 = amountBX * price / ONE * (ONE - maxSlippageRatio) / ONE;
        address swapper = _getBaseSwapper(tokenWETH);
        (resultBX, resultB0) = IBaseSwapper(swapper).swapExactTokensForTokens{value: amountBX}(
            msg.sender, tokenWETH, tokenB0, amountBX, minAmountB0
        );
    }

    function swapB0ForExactETH(uint256 maxAmountB0, uint256 amountBX)
    external returns (uint256 resultB0, uint256 resultBX)
    {
        uint256 price = getTokenPrice(tokenWETH);
        uint256 maxSlippageRatio = getMaxSlippageRatio(tokenWETH);
        uint256 maxB0 = amountBX * price / ONE * (ONE + maxSlippageRatio) / ONE;
        address swapper = _getBaseSwapper(tokenWETH);
        if (maxAmountB0 >= maxB0) {
            IERC20(tokenB0).safeTransferFrom(msg.sender, swapper, maxB0);
            (resultB0, resultBX) = IBaseSwapper(swapper).swapTokensForExactTokens(
                msg.sender, tokenB0, tokenWETH, maxB0, amountBX
            );
        } else {
            uint256 minAmountBX = maxAmountB0 * (ONE - maxSlippageRatio) / price;
            IERC20(tokenB0).safeTransferFrom(msg.sender, swapper, maxAmountB0);
            (resultB0, resultBX) = IBaseSwapper(swapper).swapExactTokensForTokens(
                msg.sender, tokenB0, tokenWETH, maxAmountB0, minAmountBX
            );
        }
    }

    function swapETHForExactB0(uint256 amountB0)
    external payable returns (uint256 resultB0, uint256 resultBX)
    {
        uint256 price = getTokenPrice(tokenWETH);
        uint256 maxSlippageRatio = getMaxSlippageRatio(tokenWETH);
        uint256 maxAmountBX = msg.value;
        uint256 maxBX = amountB0 * (ONE + maxSlippageRatio) / price;
        address swapper = _getBaseSwapper(tokenWETH);
        if (maxAmountBX >= maxBX) {
            (resultBX, resultB0) = IBaseSwapper(swapper).swapTokensForExactTokens{value: maxAmountBX}(
                msg.sender, tokenWETH, tokenB0, maxAmountBX, amountB0
            );
        } else {
            uint256 minAmountB0 = maxAmountBX * price / ONE * (ONE - maxSlippageRatio) / ONE;
            (resultBX, resultB0) = IBaseSwapper(swapper).swapExactTokensForTokens{value: maxAmountBX}(
                msg.sender, tokenWETH, tokenB0, maxAmountBX, minAmountB0
            );
        }
    }

    function _getBaseSwapper(address tokenBX) internal view returns (address baseSwapper) {
        baseSwapper = baseSwappers[tokenBX];
        require(baseSwapper != address(0), 'No base swapper');
    }

}
