// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface ILiqClaim {

    struct Claimable {
        address bToken;
        uint256 amount;
    }

    function getClaimables(address owner) external view returns (Claimable[] memory);

    function getTotalAmount(address bToken) external view returns (uint256);

    function deposit(address owner, address bToken, uint256 amount) external;

    function redeem() external;

}
