// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface ILayerbankCore {

    struct MarketInfo {
        bool isListed;
        uint256 supplyCap;
        uint256 borrowCap;
        uint256 collateralFactor;
    }

    function marketInfoOf(address gToken) external view returns (MarketInfo memory);

    function claimLab() external;

    function supply(address gToken, uint256 uAmount) external payable returns (uint256);

    function redeemToken(address gToken, uint256 gAmount) external returns (uint256);

    function redeemUnderlying(address gToken, uint256 uAmount) external returns (uint256);

}
