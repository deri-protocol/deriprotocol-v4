// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '@openzeppelin/contracts/interfaces/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import '../../utils/Admin.sol';

contract BaseSwapperUniswapV2 is Admin {

    using SafeERC20 for IERC20;

    IUniswapV2Factory public immutable factory;

    IUniswapV2Router02 public immutable router;

    address public immutable tokenWETH;

    // fromToken => toToken => path
    mapping(address => mapping(address => address[])) internal paths;

    constructor (address factory_, address router_, address tokenWETH_) {
        factory = IUniswapV2Factory(factory_);
        router = IUniswapV2Router02(router_);
        tokenWETH = tokenWETH_;
    }

    function isSupportedSwap(address token1, address token2) public view returns (bool) {
        return paths[token1][token2].length > 0;
    }

    function getPath(address token1, address token2) public view returns (address[] memory) {
        return paths[token1][token2];
    }

    function setPath(address[] memory path) external _onlyAdmin_ {
        uint256 length = path.length;

        require(length >= 2, 'Invalid path');
        for (uint256 i = 1; i < length; i++) {
            require(factory.getPair(path[i-1], path[i]) != address(0), 'Invalid path');
        }

        address[] memory revertedPath = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            revertedPath[length-i-1] = path[i];
        }

        address token1 = path[0];
        address token2 = path[length-1];

        paths[token1][token2] = path;
        paths[token2][token1] = revertedPath;

        IERC20(token1).approve(address(router), type(uint256).max);
        IERC20(token2).approve(address(router), type(uint256).max);
    }

    receive() external payable {}

    //================================================================================

    function swapExactTokensForTokens(address recipient, address token1, address token2, uint256 amount1, uint256 amount2)
    external payable returns (uint256 result1, uint256 result2)
    {
        if (amount1 == 0) return (0, 0);

        uint256[] memory res;

        if (token1 == tokenWETH) {
            require(amount1 == msg.value, 'Invalid value');
            res = router.swapExactETHForTokens{value: amount1}(
                amount2,
                paths[token1][token2],
                recipient,
                block.timestamp
            );
        } else if (token2 == tokenWETH) {
            res = router.swapExactTokensForETH(
                amount1,
                amount2,
                paths[token1][token2],
                recipient,
                block.timestamp
            );
        } else {
            res = router.swapExactTokensForTokens(
                amount1,
                amount2,
                paths[token1][token2],
                recipient,
                block.timestamp
            );
        }

        result1 = res[0];
        result2 = res[res.length - 1];
    }

    function swapTokensForExactTokens(address recipient, address token1, address token2, uint256 amount1, uint256 amount2)
    external payable returns (uint256 result1, uint256 result2)
    {
        if (amount1 == 0 || amount2 == 0) return (0, 0);

        uint256[] memory res;

        if (token1 == tokenWETH) {
            require(amount1 == msg.value, 'Invalid value');
            res = router.swapETHForExactTokens{value: amount1}(
                amount2,
                paths[token1][token2],
                recipient,
                block.timestamp
            );
        } else if (token2 == tokenWETH) {
            res = router.swapTokensForExactETH(
                amount2,
                amount1,
                paths[token1][token2],
                recipient,
                block.timestamp
            );
        } else {
            res = router.swapTokensForExactTokens(
                amount2,
                amount1,
                paths[token1][token2],
                recipient,
                block.timestamp
            );
        }

        result1 = res[0];
        result2 = res[res.length - 1];

        if (token1 == tokenWETH) {
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
