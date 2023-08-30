// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IVault {

    struct VaultParam {
        address lToken;
        address pToken;
        address oracle;
        address swapper;
        address iou;
        address tokenB0;
        address eventSigner;
        uint256 b0ReserveRatio;
        int256  liquidationRewardCutRatio;
        int256  minLiquidationReward;
        int256  maxLiquidationReward;
    }

    struct VaultState {
        uint256 st0Amount;
        int256  cumulativePnlOnVault;
        uint256 liquidityTime;
        uint256 totalLiquidity;
        int256  cumulativeTimePerLiquidity;
    }

    struct BTokenState {
        address bToken;
        bool    initialized;
        uint256 custodian;
        bytes32 oracleId;
        uint256 collateralFactor;
        uint256 stTotalAmount;
    }

    struct LpState {
        uint256 requestId;
        address bToken;
        uint256 stAmount;
        int256  b0Amount;
        int256  lastCumulativePnlOnEngine;
        uint256 liquidity;
        uint256 cumulativeTime;
        uint256 lastCumulativeTimePerLiquidity;
    }

    struct TdState {
        uint256 requestId;
        address bToken;
        uint256 stAmount;
        int256  b0Amount;
        int256  lastCumulativePnlOnEngine;
    }

    struct VarOnCallbackAddLiquidity {
        uint256 requestId;
        uint256 lTokenId;
        uint256 liquidity;
        uint256 totalLiquidity;
        int256  cumulativePnlOnEngine;
    }

    struct VarOnCallbackRemoveLiquidity {
        uint256 requestId;
        uint256 lTokenId;
        uint256 liquidity;
        uint256 totalLiquidity;
        int256  cumulativePnlOnEngine;
        uint256 bAmount;
    }

    struct VarOnCallbackRemoveMargin {
        uint256 requestId;
        uint256 pTokenId;
        uint256 requiredMargin;
        int256  cumulativePnlOnEngine;
        uint256 bAmount;
    }

    struct VarOnCallbackLiquidate {
        uint256 requestId;
        uint256 pTokenId;
        int256  cumulativePnlOnEngine;
    }

}
