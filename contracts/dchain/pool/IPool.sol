// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IPool {

    struct PoolParam {
        address symbolManager;
        address oracle;
        address iChainEventSigner;
        int256  initialMarginMultiplier;
        int256  protocolFeeCollectRatio;
    }

    struct PoolState {
        int256 totalLiquidity;
        int256 lpsPnl;
        int256 cumulativePnlPerLiquidity;
        int256 protocolFee;
    }

    struct ChainState {
        int256 lastCumulativePnlOnGateway;
    }

    struct LpState {
        uint256 requestId;
        int256  cumulativePnl;
        int256  liquidity;
        int256  cumulativePnlPerLiquidity;
    }

    struct TdState {
        uint256 requestId;
        int256  cumulativePnl;
        bool    liquidated;
    }

    struct VarOnUpdateLiquidity {
        uint256 requestId;
        uint256 lTokenId;
        uint256 liquidity;
        int256  lastCumulativePnlOnEngine;
        int256  cumulativePnlOnGateway;
        uint256 removeBAmount;
    }

    struct VarOnRemoveMargin {
        uint256 requestId;
        uint256 pTokenId;
        uint256 margin;
        int256  lastCumulativePnlOnEngine;
        int256  cumulativePnlOnGateway;
        uint256 bAmount;
    }

    struct VarOnTrade {
        uint256 requestId;
        uint256 pTokenId;
        uint256 margin;
        int256  lastCumulativePnlOnEngine;
        int256  cumulativePnlOnGateway;
        bytes32 symbolId;
        int256[] tradeParams;
    }

    struct VarOnLiquidate {
        uint256 requestId;
        uint256 pTokenId;
        uint256 margin;
        int256  lastCumulativePnlOnEngine;
        int256  cumulativePnlOnGateway;
    }

    struct VarOnTradeAndRemoveMargin {
        uint256 requestId;
        uint256 pTokenId;
        uint256 margin;
        int256  lastCumulativePnlOnEngine;
        int256  cumulativePnlOnGateway;
        uint256 bAmount;
        bytes32 symbolId;
        int256[] tradeParams;
    }

}
