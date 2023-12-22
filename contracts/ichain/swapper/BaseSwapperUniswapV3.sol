// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '@openzeppelin/contracts/interfaces/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@aave/core-v3/contracts/misc/interfaces/IWETH.sol';
import '../../utils/Admin.sol';

contract BaseSwapperUniswapV3 is Admin {

    using SafeERC20 for IERC20;

    IUniswapV3Factory public immutable factory;

    ISwapRouter public immutable router;

    address public immutable tokenWETH;

    // fromToken => toToken => path
    mapping (address => mapping (address => bytes)) internal paths;

    constructor (address factory_, address router_, address tokenWETH_) {
        factory = IUniswapV3Factory(factory_);
        router = ISwapRouter(router_);
        tokenWETH = tokenWETH_;
    }

    function isSupportedSwap(address token1, address token2) public view returns (bool) {
        return paths[token1][token2].length > 0;
    }

    function getPath(address token1, address token2) public view returns (bytes memory) {
        return paths[token1][token2];
    }

    // Path is constructed as: [tokens[0], fees[0], tokens[1], fees[1], ... tokens[N-1]]
    function setPath(address[] memory tokens, uint24[] memory fees) external _onlyAdmin_ {
        uint256 length = fees.length;
        require(length >= 1 && tokens.length == length + 1, 'Invalid path');

        bytes memory path;

        // Forward path
        path = abi.encodePacked(tokens[0]);
        for (uint256 i = 0; i < length; i++) {
            require(
                factory.getPool(tokens[i], tokens[i+1], fees[i]) != address(0),
                'Invalid path'
            );
            path = abi.encodePacked(path, fees[i], tokens[i+1]);
        }
        paths[tokens[0]][tokens[length]] = path;

        // Backward path
        path = abi.encodePacked(tokens[length]);
        for (uint256 i = length; i > 0; i--) {
            path = abi.encodePacked(path, fees[i-1], tokens[i-1]);
        }
        paths[tokens[length]][tokens[0]] = path;

        IERC20(tokens[0]).approve(address(router), type(uint256).max);
        IERC20(tokens[length]).approve(address(router), type(uint256).max);
    }

    receive() external payable {}

    //================================================================================

    function swapExactTokensForTokens(address recipient, address token1, address token2, uint256 amount1, uint256 amount2)
    external payable returns (uint256 result1, uint256 result2)
    {
        if (amount1 == 0) return (0, 0);

        if (token1 == tokenWETH) {
            require(amount1 == msg.value, 'Invalid value');
        }

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: paths[token1][token2],
            recipient: token2 == tokenWETH ? address(this) : recipient,
            deadline: block.timestamp,
            amountIn: amount1,
            amountOutMinimum: amount2
        });
        uint256 amountOut = router.exactInput{value: token1 == tokenWETH ? amount1 : 0}(params);

        if (token2 == tokenWETH) {
            IWETH(tokenWETH).withdraw(amountOut);
            _sendETH(recipient, amountOut);
        }

        result1 = amount1;
        result2 = amountOut;
    }

    function swapTokensForExactTokens(address recipient, address token1, address token2, uint256 amount1, uint256 amount2)
    external payable returns (uint256 result1, uint256 result2)
    {
        if (amount1 == 0 || amount2 == 0) return (0, 0);

        if (token1 == tokenWETH) {
            require(amount1 == msg.value, 'Invalid value');
        }

        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
            path: paths[token2][token1],
            recipient: token2 == tokenWETH ? address(this) : recipient,
            deadline: block.timestamp,
            amountOut: amount2,
            amountInMaximum: amount1
        });
        uint256 amountIn = router.exactOutput{value: token1 == tokenWETH ? amount1 : 0}(params);

        if (token2 == tokenWETH) {
            IWETH(tokenWETH).withdraw(amount2);
            _sendETH(recipient, amount2);
        }

        result1 = amountIn;
        result2 = amount2;

        if (token1 == tokenWETH) {
            router.refundETH();
            _sendETH(recipient, address(this).balance);
        } else {
            IERC20(token1).safeTransfer(recipient, IERC20(token1).balanceOf(address(this)));
        }
    }

    function _sendETH(address to, uint256 amount) internal {
        (bool success, ) = payable(to).call{value: amount}('');
        require(success, 'Send ETH fail');
    }

}

interface IUniswapV3Factory {
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);
}

interface ISwapRouter {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
    struct ExactOutputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
    }
    function exactOutput(ExactOutputParams calldata params) external payable returns (uint256 amountIn);
    function refundETH() external;
}
