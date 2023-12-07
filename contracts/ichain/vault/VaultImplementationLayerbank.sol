// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './ILayerbankCore.sol';
import './ILayerbankMarket.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '../../library/ETHAndERC20.sol';
import '../../library/SafeMath.sol';
import './VaultStorage.sol';

/**
 * @title Layerbank Protocol Vault Implementation
 * @dev This contract serves as a vault for managing deposits within the Layerbank protocol.
 */
contract VaultImplementationLayerbank is VaultStorage {

    using SafeERC20 for IERC20;
    using ETHAndERC20 for address;
    using SafeMath for uint256;

    error OnlyGateway();
    error DepositError();
    error RedeemError();

    uint256 constant UONE = 1e18;
    address constant assetETH = address(1);

    address public immutable gateway;
    address public immutable asset;         // Underlying asset, e.g. USDC
    address public immutable market;        // Layerbank market, e.g. lUSDC
    address public immutable layerbankCore; // Layerbank Core contract
    address public immutable rewardToken;   // Layerbank Token, LAB

    modifier _onlyGateway_() {
        if (msg.sender != gateway) {
            revert OnlyGateway();
        }
        _;
    }

    constructor (
        address gateway_,
        address market_,
        address layerbankCore_,
        address rewardToken_
    ) {
        gateway = gateway_;

        ILayerbankCore.MarketInfo memory info = ILayerbankCore(layerbankCore_).marketInfoOf(market_);
        require(info.isListed);

        address asset_ = ILayerbankMarket(market_).underlying();
        if (asset_ == address(0)) asset_ = assetETH;
        asset = asset_;

        market = market_;
        layerbankCore = layerbankCore_;
        rewardToken = rewardToken_;
    }

    function enterMarket() external _onlyAdmin_ {
        if (asset != assetETH) {
            asset.approveMax(market);
        }
    }

    function exitMarket() external _onlyAdmin_ {
        if (asset != assetETH) {
            asset.unapprove(market);
        }
    }

    function claimReward(address to) external _onlyAdmin_ {
        ILayerbankCore(layerbankCore).claimLab();
        uint256 amount = rewardToken.balanceOfThis();
        if (amount > 0) {
            IERC20(rewardToken).safeTransfer(to, amount);
        }
    }

    // @notice Get the asset token balance belonging to a specific 'dTokenId'
    function getBalance(uint256 dTokenId) external view returns (uint256 balance) {
        uint256 stAmount = stAmounts[dTokenId];
        if (stAmount != 0) {
            // mAmount is the market token (e.g. lUSDC) balance associated with dTokenId
            uint256 mAmount = market.balanceOfThis() * stAmount / stTotalAmount;
            // Layerbank exchange rate which convert market amount to asset amount, e.g. lUSDC to USDC
            uint256 exRate = ILayerbankMarket(market).exchangeRate();
            // Balance in asset, e.g. USDC
            balance = exRate * mAmount / UONE;
        }
    }

    /**
     * @notice Deposit assets into the vault associated with a specific 'dTokenId'.
     * @param dTokenId The unique identifier of the dToken.
     * @param amount The amount of assets to deposit.
     * @return mintedSt The amount of staked tokens ('mintedSt') received in exchange for the deposited assets.
     */
    function deposit(uint256 dTokenId, uint256 amount) external payable _onlyGateway_ returns (uint256 mintedSt) {
        uint256 m1 = market.balanceOfThis();
        uint256 mAmount;
        if (asset == assetETH) {
            amount = msg.value;
            mAmount = ILayerbankCore(layerbankCore).supply{value: amount}(market, amount);
        } else {
            asset.transferIn(gateway, amount);
            mAmount = ILayerbankCore(layerbankCore).supply(market, amount);
        }
        uint256 m2 = market.balanceOfThis();

        if (m1 + mAmount != m2) {
            revert DepositError();
        }

        // Calculate the 'mintedSt' based on changes in the market balance and staked amount ratios
        // `mintedSt` is in 18 decimals
        mintedSt = m1 == 0
            ? m2.rescale(market.decimals(), 18)
            : mAmount * stTotalAmount / m1;

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
        uint256 m1 = market.balanceOfThis();
        uint256 a1 = asset.balanceOfThis();

        uint256 stAmount = stAmounts[dTokenId];
        uint256 stTotal = stTotalAmount;

        if (stAmount == 0) return 0;

        uint256 mAmount = m1 * stAmount / stTotal;

        {
            // Calculate the market token amount ('mAmount') and available assets ('available') for redemption
            uint256 exRate = ILayerbankMarket(market).exchangeRate();
            uint256 available = exRate * mAmount / UONE;

            if (amount >= available) {
                redeemedAmount = ILayerbankCore(layerbankCore).redeemToken(market, mAmount);
            } else {
                redeemedAmount = ILayerbankCore(layerbankCore).redeemUnderlying(market, amount);
            }
        }

        uint256 m2 = market.balanceOfThis();
        uint256 a2 = asset.balanceOfThis();

        if (a1 + redeemedAmount != a2) {
            revert RedeemError();
        }

        // Calculate the staked tokens burned ('burnedSt') based on the change in market balances and staked amount ratios
        uint256 burnedSt = m1 - m2 == mAmount
            ? stAmount
            : ((m1 - m2) * stTotal).divRoundingUp(m1);

        // Update the staked amount for 'dTokenId' and the total staked amount
        stAmounts[dTokenId] -= burnedSt;
        stTotalAmount -= burnedSt;

        asset.transferOut(gateway, redeemedAmount);
    }

}
