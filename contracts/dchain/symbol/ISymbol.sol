// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface ISymbol {

    struct SettlementOnAddLiquidity {
        bool settled;
        int256 funding;
        int256 diffTradersPnl;
        int256 diffInitialMarginRequired;
    }

    struct SettlementOnRemoveLiquidity {
        bool settled;
        int256 funding;
        int256 diffTradersPnl;
        int256 diffInitialMarginRequired;
        int256 removeLiquidityPenalty;
    }

    struct SettlementOnTraderWithPosition {
        int256 funding;
        int256 diffTradersPnl;
        int256 diffInitialMarginRequired;
        int256 traderFunding;
        int256 traderPnl;
        int256 traderInitialMarginRequired;
    }

    struct SettlementOnTrade {
        int256 funding;
        int256 diffTradersPnl;
        int256 diffInitialMarginRequired;
        int256 traderFunding;
        int256 traderPnl;
        int256 traderInitialMarginRequired;
        int256 tradeCost;
        int256 tradeFee;
        int256 tradeRealizedCost;
        int256 positionChange; // Enum value, 1: new open (enter), -1: total close (exit), 2: increase volume, -2: decrease volume (partial close)
    }

    struct SettlementOnLiquidate {
        int256 funding;
        int256 diffTradersPnl;
        int256 diffInitialMarginRequired;
        int256 traderFunding;
        int256 traderPnl;
        int256 traderMaintenanceMarginRequired;
        int256 tradeVolume;
        int256 tradeCost;
        int256 tradeRealizedCost;
    }

    struct SettlementOnForceClose {
        int256 funding;
        int256 diffTradersPnl;
        int256 diffInitialMarginRequired;
        int256 traderFunding;
        int256 tradeCost;
        int256 tradeRealizedCost;
    }

}
