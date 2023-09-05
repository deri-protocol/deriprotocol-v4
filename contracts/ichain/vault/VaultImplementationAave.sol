// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '@aave/core-v3/contracts/interfaces/IPool.sol';
import '@aave/core-v3/contracts/misc/interfaces/IWETH.sol';
import '@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '../../library/ETHAndERC20.sol';
import '../../library/SafeMath.sol';
import './VaultStorage.sol';

contract VaultImplementationAave is VaultStorage {

    using SafeERC20 for IERC20;
    using ETHAndERC20 for address;
    using SafeMath for uint256;

    error OnlyVault();
    error WithdrawError();

    uint256 constant UONE = 1e18;
    address constant assetETH = address(1);

    address public immutable vault;
    address public immutable asset;
    address public immutable market;
    address public immutable weth;
    address public immutable aavePool;
    address public immutable rewardController;

    modifier _onlyVault_() {
        if (msg.sender != vault) {
            revert OnlyVault();
        }
        _;
    }

    constructor (
        address vault_,
        address market_,
        address weth_,
        address aavePool_,
        address rewardController_
    ) {
        vault = vault_;

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

    function getBalance(uint256 dTokenId) external view returns (uint256 balance) {
        uint256 stAmount = stAmounts[dTokenId];
        if (stAmount != 0) {
            balance = market.balanceOfThis() * stAmount / stTotalAmount;
        }
    }

    function deposit(uint256 dTokenId, uint256 amount) external payable _onlyVault_ returns (uint256 mintedSt) {
        if (asset == assetETH) {
            amount = msg.value;
            IWETH(weth).deposit{value: amount}();
            IPool(aavePool).supply(weth, amount, address(this), 0);
        } else {
            asset.transferIn(vault, amount);
            IPool(aavePool).supply(asset, amount, address(this), 0);
        }

        uint256 stTotal = stTotalAmount;
        if (stTotal == 0) {
            mintedSt = amount.rescale(asset.decimals(), 18);
        } else {
            uint256 amountTotal = market.balanceOfThis();
            mintedSt = stTotal * amount / (amountTotal - amount);
        }

        stAmounts[dTokenId] += mintedSt;
        stTotalAmount += mintedSt;
    }

    function redeem(uint256 dTokenId, uint256 amount) external _onlyVault_ returns (uint256 redeemedAmount) {
        uint256 stAmount = stAmounts[dTokenId];
        uint256 stTotal = stTotalAmount;

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

        uint256 burnedSt = stTotal * amount / amountTotal;
        stAmounts[dTokenId] -= burnedSt;
        stTotalAmount -= burnedSt;

        asset.transferOut(vault, redeemedAmount);
    }

}

interface IMarket {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}
