// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '@aave/core-v3/contracts/interfaces/IPool.sol';
import '@aave/core-v3/contracts/misc/interfaces/IWETH.sol';
import '@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '../../library/ETHAndERC20.sol';
import '../../library/SafeMath.sol';
import './VaultStorage.sol';

/**
 * @title Aave Protocol Vault Implementation
 * @dev This contract serves as a vault for managing deposits within the Aave protocol.
 */
contract VaultImplementationAave is VaultStorage {

    using SafeERC20 for IERC20;
    using ETHAndERC20 for address;
    using SafeMath for uint256;

    error OnlyGateway();
    error WithdrawError();

    uint256 constant UONE = 1e18;
    address constant assetETH = address(1);

    address public immutable gateway;
    address public immutable asset;             // Underlying asset, e.g. WBTC
    address public immutable market;            // Aave market, e.g. aArbWBTC
    address public immutable weth;              // Wrapped ETH contract
    address public immutable aavePool;          // Aave pool
    address public immutable rewardController;  // Aave reward controller

    modifier _onlyGateway_() {
        if (msg.sender != gateway) {
            revert OnlyGateway();
        }
        _;
    }

    constructor (
        address gateway_,
        address market_,
        address weth_,
        address aavePool_,
        address rewardController_
    ) {
        gateway = gateway_;

        address asset_ = IMarket(market_).UNDERLYING_ASSET_ADDRESS();
        if (asset_ == weth_) {
            asset_ = assetETH;
        }
        asset = asset_;

        market = market_;
        weth = weth_;
        aavePool = aavePool_;
        rewardController = rewardController_;
    }

    function enterMarket() external _onlyAdmin_ {
        if (asset == assetETH) {
            weth.approveMax(aavePool);
        } else {
            asset.approveMax(aavePool);
        }
    }

    function exitMarket() external _onlyAdmin_ {
        if (asset == assetETH) {
            weth.unapprove(aavePool);
        } else {
            asset.unapprove(aavePool);
        }
    }

    function claimReward(address to, address[] memory assets) external _onlyAdmin_ {
        (address[] memory rewardsList, uint256[] memory claimedAmounts)
            = IRewardsController(rewardController).claimAllRewardsToSelf(assets);
        for (uint256 i = 0; i < rewardsList.length; i++) {
            if (claimedAmounts[i] > 0) {
                IERC20(rewardsList[i]).safeTransfer(to, claimedAmounts[i]);
            }
        }
    }

    // @notice Get the asset token balance belonging to a specific 'dTokenId'
    function getBalance(uint256 dTokenId) external view returns (uint256 balance) {
        uint256 stAmount = stAmounts[dTokenId];
        if (stAmount != 0) {
            balance = market.balanceOfThis() * stAmount / stTotalAmount;
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
            IWETH(weth).deposit{value: amount}();
            IPool(aavePool).supply(weth, amount, address(this), 0);
        } else {
            asset.transferIn(gateway, amount);
            IPool(aavePool).supply(asset, amount, address(this), 0);
        }

        // Calculate the 'mintedSt' based on the total staked amount ('stTotal') and the amount of assets deposited ('amount')
        // `mintedSt` is in 18 decimals
        uint256 stTotal = stTotalAmount;
        if (stTotal == 0) {
            mintedSt = amount.rescale(asset.decimals(), 18);
        } else {
            uint256 amountTotal = market.balanceOfThis();
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
        uint256 amountTotal = market.balanceOfThis();
        uint256 available = amountTotal * stAmount / stTotal;
        if (amount > available) amount = available;

        if (asset == assetETH) {
            redeemedAmount = IPool(aavePool).withdraw(weth, amount, address(this));
            IWETH(weth).withdraw(redeemedAmount);
        } else {
            redeemedAmount = IPool(aavePool).withdraw(asset, amount, address(this));
        }

        if (redeemedAmount != amount) {
            revert WithdrawError();
        }

        // Calculate the staked tokens burned ('burnedSt') based on changes in the total asset balance
        uint256 burnedSt = amount == available
            ? stAmount
            : (stTotal * amount).divRoundingUp(amountTotal);

        // Update the staked amount for 'dTokenId' and the total staked amount
        stAmounts[dTokenId] -= burnedSt;
        stTotalAmount -= burnedSt;

        asset.transferOut(gateway, redeemedAmount);
    }

}

interface IMarket {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}
