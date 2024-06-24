// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface ISymbolManager {

    struct SettlementOnAddLiquidity {
        int256 funding;
        int256 diffTradersPnl;
    }

    struct SettlementOnRemoveLiquidity {
        int256 funding;
        int256 diffTradersPnl;
        int256 initialMarginRequired;
        int256 removeLiquidityPenalty;
    }

    struct SettlementOnRemoveMargin {
        int256 funding;
        int256 diffTradersPnl;
        int256 traderFunding;
        int256 traderPnl;
        int256 traderInitialMarginRequired;
    }

    struct SettlementOnTrade {
        int256 funding;
        int256 diffTradersPnl;
        int256 initialMarginRequired;
        int256 traderFunding;
        int256 traderPnl;
        int256 traderInitialMarginRequired;
        int256 tradeFee;
        int256 tradeRealizedCost;
    }

    struct SettlementOnLiquidate {
        int256 funding;
        int256 diffTradersPnl;
        int256 traderFunding;
        int256 traderPnl;
        int256 traderMaintenanceMarginRequired;
        int256 tradeRealizedCost;
    }

    struct SettlementOnForceClose {
        int256 funding;
        int256 diffTradersPnl;
        int256 initialMarginRequired;
        int256 traderFunding;
        int256 tradeRealizedCost;
    }

    function getSymbolId(string memory symbol, uint8 category) external pure returns (bytes32 symbolId);

    function getCategory(bytes32 symbolId) external pure returns (uint8);

    function getSymbolIds() external view returns (bytes32[] memory);

    function getPTokenIdsOfSymbol(bytes32 symbolId) external view returns (uint256[] memory);

    function getSymbolIdsOfPToken(uint256 pTokenId) external view returns (bytes32[] memory);

    function getState(bytes32 symbolId) external view returns (bytes32[] memory s);

    function getPosition(bytes32 symbolId, uint256 pTokenId) external view returns (bytes32[] memory pos);

    function addSymbol(string memory symbol, uint8 category, bytes32[] memory p) external;

    function setParameterOfId(string memory symbol, uint8 category, uint8 parameterId, bytes32 value) external;

    function setParameterOfIdForCategory(uint8 category, uint8 parameterId, bytes32 value) external;

    function settleSymbolsOnAddLiquidity(int256 liquidity)
    external returns (SettlementOnAddLiquidity memory ss);

    function settleSymbolsOnRemoveLiquidity(int256 liquidity, int256 removedLiquidity)
    external returns (SettlementOnRemoveLiquidity memory ss);

    function settleSymbolsOnRemoveMargin(uint256 pTokenId, int256 liquidity)
    external returns (SettlementOnRemoveMargin memory ss);

    function settleSymbolsOnTrade(bytes32 symbolId, uint256 pTokenId, int256 liquidity, int256[] memory tradeParams)
    external returns (SettlementOnTrade memory ss);

    function settleSymbolOnForceClose(bytes32 symbolId, uint256 pTokenId, int256 liquidity)
    external returns (ISymbolManager.SettlementOnForceClose memory ss);

    function settleSymbolsOnLiquidate(uint256 pTokenId, int256 liquidity)
    external returns (SettlementOnLiquidate memory ss);

}
