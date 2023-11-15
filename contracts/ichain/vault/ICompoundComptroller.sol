// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface ICompoundComptroller {

    function enterMarkets(address[] memory cTokens) external returns (uint256[] memory errors);

    function exitMarket(address cTokenAddress) external returns (uint256 error);

    function claimComp(address holder) external;

}
