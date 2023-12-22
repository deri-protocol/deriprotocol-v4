// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IBaseSwapper {

    function tokenWETH() external view returns (address);

    function isSupportedSwap(address token1, address token2) external view returns (bool);

    function swapExactTokensForTokens(address recipient, address token1, address token2, uint256 amount1, uint256 amount2)
    external payable returns (uint256 result1, uint256 result2);

    function swapTokensForExactTokens(address recipient, address token1, address token2, uint256 amount1, uint256 amount2)
    external payable returns (uint256 result1, uint256 result2);

}
