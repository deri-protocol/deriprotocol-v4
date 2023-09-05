// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IVault {

    function stAmounts(uint256 dTokenId) external view returns (uint256);

    function stTotalAmount() external view returns (uint256);

    function requester() external view returns (address);

    function asset() external view returns (address);

    function getBalance(uint256 dTokenId) external view returns (uint256 balance);

    function deposit(uint256 dTokenId, uint256 amount) external payable returns (uint256 mintedSt);

    function redeem(uint256 dTokenId, uint256 amount) external returns (uint256 redeemedAmount);

}
