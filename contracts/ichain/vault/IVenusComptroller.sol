// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IVenusComptroller {

    function enterMarkets(address[] calldata vTokens) external returns (uint256[] memory errors);

    function exitMarket(address vToken) external returns (uint256 error);

    function claimVenus(address account) external;

}
