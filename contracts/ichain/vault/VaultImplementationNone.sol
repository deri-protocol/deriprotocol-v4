// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../../library/ETHAndERC20.sol';
import '../../library/SafeMath.sol';
import './VaultStorage.sol';

contract VaultImplementationNone is VaultStorage {

    using ETHAndERC20 for address;
    using SafeMath for uint256;

    error OnlyGateway();

    uint256 constant UONE = 1e18;
    address constant assetETH = address(1);

    address public immutable gateway;
    address public immutable asset;

    modifier _onlyGateway_() {
        if (msg.sender != gateway) {
            revert OnlyGateway();
        }
        _;
    }

    constructor (address gateway_, address asset_) {
        gateway = gateway_;
        asset = asset_;
    }

    function getBalance(uint256 dTokenId) external view returns (uint256 balance) {
        uint256 stAmount = stAmounts[dTokenId];
        if (stAmount != 0) {
            balance = asset.balanceOfThis() * stAmount / stTotalAmount;
        }
    }

    function deposit(uint256 dTokenId, uint256 amount) external payable _onlyGateway_ returns (uint256 mintedSt) {
        if (asset == assetETH) {
            amount = msg.value;
        } else {
            asset.transferIn(gateway, amount);
        }

        uint256 stTotal = stTotalAmount;
        if (stTotal == 0) {
            mintedSt = amount.rescale(asset.decimals(), 18);
        } else {
            uint256 amountTotal = asset.balanceOfThis();
            mintedSt = stTotal * amount / (amountTotal - amount);
        }

        stAmounts[dTokenId] += mintedSt;
        stTotalAmount += mintedSt;
    }

    function redeem(uint256 dTokenId, uint256 amount) external _onlyGateway_ returns (uint256 redeemedAmount) {
        uint256 stAmount = stAmounts[dTokenId];
        uint256 stTotal = stTotalAmount;

        uint256 amountTotal = asset.balanceOfThis();
        uint256 available = amountTotal * stAmount / stTotal;
        redeemedAmount = SafeMath.min(amount, available);

        uint256 burnedSt = stTotal * redeemedAmount / amountTotal;
        stAmounts[dTokenId] -= burnedSt;
        stTotalAmount -= burnedSt;

        asset.transferOut(gateway, redeemedAmount);
    }

}
