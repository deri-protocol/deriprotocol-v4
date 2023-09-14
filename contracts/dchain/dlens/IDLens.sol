// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../engine/IEngine.sol';

interface IDLens {

    struct EngineState {
        address symbolManager;
        address oracle;
        address iChainEventSigner;
        int256  initialMarginMultiplier;
        int256  protocolFeeCollectRatio;
        int256  totalLiquidity;
        int256  lpsPnl;
        int256  cumulativePnlPerLiquidity;
        int256  protocolFee;
    }

    struct SymbolState {
        string  symbol;
        bytes32 symbolId;
        string  category;
        bytes32 priceId;
        bytes32 volatilityId;
        int256  fundingPeriod;
        int256  minTradeVolume;
        int256  strikePrice;
        int256  alpha;
        int256  feeRatio;
        int256  feeRatioNotional;
        int256  feeRatioMark;
        int256  initialMarginRatio;
        int256  maintenanceMarginRatio;
        int256  minInitialMarginRatio;
        int256  startingPriceShiftLimit;
        bool    isCall;
        bool    isCloseOnly;
        int256  lastTimestamp;
        int256  lastIndexPrice;
        int256  lastVolatility;
        int256  netVolume;
        int256  netCost;
        int256  openVolume;
        int256  tradersPnl;
        int256  initialMarginRequired;
        int256  cumulativeFundingPerVolume;
        int256  lastNetVolume;
        int256  lastNetVolumeBlock;
    }

    struct Position {
        string  symbol;
        bytes32 symbolId;
        int256  volume;
        int256  cost;
        int256  cumulativeFundingPerVolume;
    }

    struct LpState {
        uint256 lTokenId;
        uint256 requestId;
        int256  cumulativePnl;
        int256  liquidity;
        int256  cumulativePnlPerLiquidity;
    }

    struct TdState {
        uint256 pTokenId;
        uint256 requestId;
        int256  cumulativePnl;
        bool    liquidated;
        Position[] positions;
    }

}
