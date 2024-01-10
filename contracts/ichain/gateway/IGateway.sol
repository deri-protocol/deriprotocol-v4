// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IGateway {

    struct GatewayParam {
        address lToken;
        address pToken;
        address oracle;
        address swapper;
        address vault0;
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
        uint256 gatewayRequestId;
        uint256 dChainExecutionFeePerRequest;
        uint256 totalIChainExecutionFee;
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
        uint256 lastRequestIChainExecutionFee;
        uint256 cumulativeUnusedIChainExecutionFee;
    }

    struct TdState {
        uint256 requestId;
        address bToken;
        uint256 bAmount;
        int256  b0Amount;
        int256  lastCumulativePnlOnEngine;
        bool    singlePosition;
        uint256 lastRequestIChainExecutionFee;
        uint256 cumulativeUnusedIChainExecutionFee;
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

    function getGatewayState() external view returns (GatewayState memory s);

    function getBTokenState(address bToken) external view returns (BTokenState memory s);

    function getLpState(uint256 lTokenId) external view returns (LpState memory s);

    function getTdState(uint256 pTokenId) external view returns (TdState memory s);

}
