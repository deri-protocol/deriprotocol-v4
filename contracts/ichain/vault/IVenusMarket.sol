// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IVenusMarket {

    function isVToken() external view returns (bool);

    function underlying() external view returns (address);

    function exchangeRateStored() external view returns (uint256);

    function mint() external payable;

    function mint(uint256 amount) external returns (uint256 error);

    function redeem(uint256 amount) external returns (uint256 error);

    function redeemUnderlying(uint256 amount) external returns (uint256 error);

}
