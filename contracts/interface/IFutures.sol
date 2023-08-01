// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './ISymbol.sol';

interface IFutures is ISymbol {

    struct VarOnAddLiquidity {
        bytes32 symbolId;
        int256 indexPrice;
        int256 liquidity;
    }

    struct EventDataOnAddLiquidity {
        int256 indexPrice;
        int256 liquidity;
        int256 funding;
        int256 tradersPnl;
        int256 initialMarginRequired;
    }

    struct VarOnRemoveLiquidity {
        bytes32 symbolId;
        int256 indexPrice;
        int256 liquidity;
        int256 removedLiquidity;
    }

    struct EventDataOnRemoveLiquidity {
        int256 indexPrice;
        int256 liquidity;
        int256 removedLiquidity;
        int256 funding;
        int256 tradersPnl;
        int256 initialMarginRequired;
        int256 removeLiquidityPenalty;
    }

    struct VarOnTraderWithPosition {
        bytes32 symbolId;
        uint256 pTokenId;
        int256 indexPrice;
        int256 liquidity;
    }

    struct EventDataOnTraderWithPosition {
        int256 indexPrice;
        int256 liquidity;
        int256 funding;
        int256 tradersPnl;
        int256 initialMarginRequired;
        int256 traderFunding;
        int256 traderPnl;
        int256 traderInitialMarginRequired;
    }

    struct VarOnTrade {
        bytes32 symbolId;
        uint256 pTokenId;
        int256 indexPrice;
        int256 liquidity;
        int256 tradeVolume;
        int256 priceLimit;
    }

    struct EventDataOnTrade {
        int256 indexPrice;
        int256 liquidity;
        int256 tradeVolume;
        int256 funding;
        int256 tradersPnl;
        int256 initialMarginRequired;
        int256 traderFunding;
        int256 traderPnl;
        int256 traderInitialMarginRequired;
        int256 tradeCost;
        int256 tradeFee;
        int256 tradeRealizedCost;
    }

    struct VarOnLiquidate {
        bytes32 symbolId;
        uint256 pTokenId;
        int256 indexPrice;
        int256 liquidity;
    }

    struct EventDataOnLiquidate {
        int256 indexPrice;
        int256 liquidity;
        int256 funding;
        int256 tradersPnl;
        int256 initialMarginRequired;
        int256 traderFunding;
        int256 traderPnl;
        int256 traderMaintenanceMarginRequired;
        int256 tradeVolume;
        int256 tradeCost;
        int256 tradeRealizedCost;
    }

}
