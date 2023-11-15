// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface ICompoundMarket {

    function isCToken() external view returns (bool);

    function symbol() external view returns (string memory);

    function underlying() external view returns (address);

    function exchangeRateStored() external view returns (uint256);

    function mint(uint256 amount) external returns (uint256 error);

    function redeem(uint256 amount) external returns (uint256 error);

    function redeemUnderlying(uint256 amount) external returns (uint256 error);

}
