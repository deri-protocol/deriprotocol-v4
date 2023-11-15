// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../../oracle/IOracle.sol';

interface IEngine {

    struct EngineState {
        address symbolManager;
        address oracle;
        address iChainEventSigner;
        int256  initialMarginMultiplier;
        int256  protocolFeeCollectRatio;
        int256 totalLiquidity;
        int256 lpsPnl;
        int256 cumulativePnlPerLiquidity;
        uint256 protocolFee;
    }

    struct ChainState {
        int256 lastCumulativePnlOnGateway;
        uint256 lastGatewayRequestId;
        uint256 protocolFee;
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
        uint256 bAmountToRemove;
    }

    struct VarOnRemoveMargin {
        uint256 requestId;
        uint256 pTokenId;
        uint256 realMoneyMargin;
        int256  lastCumulativePnlOnEngine;
        int256  cumulativePnlOnGateway;
        uint256 bAmount;
    }

    struct VarOnTrade {
        uint256 requestId;
        uint256 pTokenId;
        uint256 realMoneyMargin;
        int256  lastCumulativePnlOnEngine;
        int256  cumulativePnlOnGateway;
        bytes32 symbolId;
        int256[] tradeParams;
    }

    struct VarOnLiquidate {
        uint256 requestId;
        uint256 pTokenId;
        uint256 realMoneyMargin;
        int256  lastCumulativePnlOnEngine;
        int256  cumulativePnlOnGateway;
    }

    struct VarOnTradeAndRemoveMargin {
        uint256 requestId;
        uint256 pTokenId;
        uint256 realMoneyMargin;
        int256  lastCumulativePnlOnEngine;
        int256  cumulativePnlOnGateway;
        uint256 bAmount;
        bytes32 symbolId;
        int256[] tradeParams;
    }

    function getEngineState() external view returns (EngineState memory s);

    function getChainState(uint88 chainId) external view returns (ChainState memory s);

    function getLpState(uint256 lTokenId) external view returns (LpState memory s);

    function getTdState(uint256 pTokenId) external view returns (TdState memory s);

    function updateLiquidity(bytes memory eventData, bytes memory eventSig, IOracle.Signature[] memory signatures) external;

    function removeMargin(bytes memory eventData, bytes memory eventSig, IOracle.Signature[] memory signatures) external;

    function trade(bytes memory eventData, bytes memory eventSig, IOracle.Signature[] memory signatures) external;

    function liquidate(bytes memory eventData, bytes memory eventSig, IOracle.Signature[] memory signatures) external;

    function tradeAndRemoveMargin(bytes memory eventData, bytes memory eventSig, IOracle.Signature[] memory signatures) external;

}
