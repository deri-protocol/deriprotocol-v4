// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../../library/ETHAndERC20.sol';
import '../../library/SafeMath.sol';
import './VaultStorage.sol';

/**
 * @title Vault Implementation with NO external custodian
 * @dev This contract serves as a vault for managing deposits without any external custodian.
 */
contract VaultImplementationNone is VaultStorage {

    using ETHAndERC20 for address;
    using SafeMath for uint256;

    error OnlyGateway();
    error TinyShareOfInitDeposit();

    uint256 constant UONE = 1e18;
    address constant assetETH = address(1);

    address public immutable gateway;
    address public immutable asset;   // Asset token, e.g. DERI

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

    // @notice Get the asset token balance belonging to a specific 'dTokenId'
    function getBalance(uint256 dTokenId) external view returns (uint256 balance) {
        uint256 stAmount = stAmounts[dTokenId];
        if (stAmount != 0) {
            balance = asset.balanceOfThis() * stAmount / stTotalAmount;
        }
    }

    /**
     * @notice Deposit assets into the vault associated with a specific 'dTokenId'.
     * @param dTokenId The unique identifier of the dToken.
     * @param amount The amount of assets to deposit.
     * @return mintedSt The amount of staked tokens ('mintedSt') received in exchange for the deposited assets.
     */
    function deposit(uint256 dTokenId, uint256 amount) external payable _onlyGateway_ returns (uint256 mintedSt) {
        if (asset == assetETH) {
            amount = msg.value;
        } else {
            asset.transferIn(gateway, amount);
        }

        // Calculate the 'mintedSt' based on the total staked amount ('stTotal') and the amount of assets deposited ('amount')
        // `mintedSt` is in 18 decimals
        uint256 stTotal = stTotalAmount;
        if (stTotal == 0) {
            mintedSt = amount.rescale(asset.decimals(), 18);
            if (mintedSt < 1e9) { // prevent an initial tiny share amount to affect later deposits
                revert TinyShareOfInitDeposit();
            }
        } else {
            uint256 amountTotal = asset.balanceOfThis();
            mintedSt = stTotal * amount / (amountTotal - amount);
        }

        // Update the staked amount for 'dTokenId' and the total staked amount
        stAmounts[dTokenId] += mintedSt;
        stTotalAmount += mintedSt;
    }

    /**
     * @notice Redeem staked tokens and receive assets from the vault associated with a specific 'dTokenId.'
     * @param dTokenId The unique identifier of the dToken.
     * @param amount The amount of asset to redeem.
     * @return redeemedAmount The amount of assets received.
     */
    function redeem(uint256 dTokenId, uint256 amount) external _onlyGateway_ returns (uint256 redeemedAmount) {
        uint256 stAmount = stAmounts[dTokenId];
        uint256 stTotal = stTotalAmount;

        // Calculate the available assets ('available') for redemption based on staked amount ratios
        uint256 amountTotal = asset.balanceOfThis();
        uint256 available = amountTotal * stAmount / stTotal;
        redeemedAmount = SafeMath.min(amount, available);

        // Calculate the staked tokens burned ('burnedSt') based on changes in the total asset balance
        uint256 burnedSt = SafeMath.min(
            (stTotal * redeemedAmount).divRoundingUp(amountTotal), stAmount
        );

        // Update the staked amount for 'dTokenId' and the total staked amount
        stAmounts[dTokenId] -= burnedSt;
        stTotalAmount -= burnedSt;

        asset.transferOut(gateway, redeemedAmount);
    }

}
