// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface ILayerbankMarket {

    function balanceOf(address account) external view returns (uint256);

    function decimals() external view returns (uint8);

    function underlying() external view returns (address);

    function exchangeRate() external view returns (uint256);

}
