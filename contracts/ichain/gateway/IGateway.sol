// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IGateway {

    struct GatewayParam {
        address lToken;
        address pToken;
        address oracle;
        address swapper;
        address iou;
        address tokenB0;
        address dChainEventSigner;
        uint256 b0ReserveRatio;
        int256  liquidationRewardCutRatio;
        int256  minLiquidationReward;
        int256  maxLiquidationReward;
    }

    struct GatewayState {
        int256  cumulativePnlOnGateway;
        uint256 liquidityTime;
        uint256 totalLiquidity;
        int256  cumulativeTimePerLiquidity;
    }

    struct BTokenState {
        address vault;
        bytes32 oracleId;
        uint256 collateralFactor;
    }

    struct LpState {
        uint256 requestId;
        address bToken;
        uint256 bAmount;
        int256  b0Amount;
        int256  lastCumulativePnlOnEngine;
        uint256 liquidity;
        uint256 cumulativeTime;
        uint256 lastCumulativeTimePerLiquidity;
    }

    struct TdState {
        uint256 requestId;
        address bToken;
        uint256 bAmount;
        int256  b0Amount;
        int256  lastCumulativePnlOnEngine;
        bool    singlePosition;
    }

    struct VarOnExecuteUpdateLiquidity {
        uint256 requestId;
        uint256 lTokenId;
        uint256 liquidity;
        uint256 totalLiquidity;
        int256  cumulativePnlOnEngine;
        uint256 bAmountToRemove;
    }

    struct VarOnExecuteRemoveMargin {
        uint256 requestId;
        uint256 pTokenId;
        uint256 requiredMargin;
        int256  cumulativePnlOnEngine;
        uint256 bAmountToRemove;
    }

    struct VarOnExecuteLiquidate {
        uint256 requestId;
        uint256 pTokenId;
        int256  cumulativePnlOnEngine;
    }

}
