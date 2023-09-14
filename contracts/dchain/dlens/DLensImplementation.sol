// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './DLensStorage.sol';
import './IDLens.sol';
import '../engine/IEngine.sol';
import '../symbol/ISymbolManager.sol';
import '../../library/Bytes32.sol';

contract DLensImplementation is DLensStorage {

    using Bytes32 for bytes32;

    IEngine immutable engine;
    ISymbolManager immutable symbolManager;

    constructor (address engine_, address symbolManager_) {
        engine = IEngine(engine_);
        symbolManager = ISymbolManager(symbolManager_);
    }

    function getSymbol(bytes32 symbolId) public pure returns (string memory) {
        return (symbolId & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00).toString();
    }

    function getCategory(bytes32 symbolId) public pure returns (uint8) {
        return uint8(uint256(symbolId));
    }

    function getEngineState() public view returns (IEngine.EngineState memory) {
        return engine.getEngineState();
    }

    function getLpState(uint256 lTokenId) public view returns (IDLens.LpState memory s) {
        IEngine.LpState memory state = engine.getLpState(lTokenId);
        s.lTokenId = lTokenId;
        s.requestId = state.requestId;
        s.cumulativePnl = state.cumulativePnl;
        s.liquidity = state.liquidity;
        s.cumulativePnlPerLiquidity = state.cumulativePnlPerLiquidity;
    }

    function getTdState(uint256 pTokenId) public view returns (IDLens.TdState memory s) {
        IEngine.TdState memory state = engine.getTdState(pTokenId);
        s.pTokenId = pTokenId;
        s.requestId = state.requestId;
        s.cumulativePnl = state.cumulativePnl;
        s.liquidated = state.liquidated;
        s.positions = getPositionsOfPToken(pTokenId);
    }

    function getSymbolState(bytes32 symbolId) public view returns (IDLens.SymbolState memory s) {
        s.symbol = getSymbol(symbolId);
        s.symbolId = symbolId;

        uint8 category = getCategory(symbolId);
        bytes32[] memory data = symbolManager.getState(symbolId);

        if (category == 1) {
            s.category = 'FUTURES';
            s.priceId = data[0];
            s.fundingPeriod = data[1].toInt();
            s.minTradeVolume = data[2].toInt();
            s.alpha = data[3].toInt();
            s.feeRatio = data[4].toInt();
            s.initialMarginRatio = data[5].toInt();
            s.maintenanceMarginRatio = data[6].toInt();
            s.startingPriceShiftLimit = data[7].toInt();
            s.isCloseOnly = data[8].toBool();
            s.lastTimestamp = data[9].toInt();
            s.lastIndexPrice = data[10].toInt();
            s.netVolume = data[11].toInt();
            s.netCost = data[12].toInt();
            s.openVolume = data[13].toInt();
            s.tradersPnl = data[14].toInt();
            s.initialMarginRequired = data[15].toInt();
            s.cumulativeFundingPerVolume = data[16].toInt();
            s.lastNetVolume = data[17].toInt();
            s.lastNetVolumeBlock = data[18].toInt();
        }
        else if (category == 2) {
            s.category = 'OPTION';
            s.priceId = data[0];
            s.volatilityId = data[1];
            s.strikePrice = data[2].toInt();
            s.fundingPeriod = data[3].toInt();
            s.minTradeVolume = data[4].toInt();
            s.alpha = data[5].toInt();
            s.feeRatioNotional = data[6].toInt();
            s.feeRatioMark = data[7].toInt();
            s.initialMarginRatio = data[8].toInt();
            s.maintenanceMarginRatio = data[9].toInt();
            s.minInitialMarginRatio = data[10].toInt();
            s.startingPriceShiftLimit = data[11].toInt();
            s.isCall = data[12].toBool();
            s.isCloseOnly = data[13].toBool();
            s.lastTimestamp = data[14].toInt();
            s.lastIndexPrice = data[15].toInt();
            s.lastVolatility = data[16].toInt();
            s.netVolume = data[17].toInt();
            s.netCost = data[18].toInt();
            s.openVolume = data[19].toInt();
            s.tradersPnl = data[20].toInt();
            s.initialMarginRequired = data[21].toInt();
            s.cumulativeFundingPerVolume = data[22].toInt();
            s.lastNetVolume = data[23].toInt();
            s.lastNetVolumeBlock = data[24].toInt();
        }
        else if (category == 3) {
            s.category = 'POWER';
            s.priceId = data[0];
            s.volatilityId = data[1];
            s.fundingPeriod = data[2].toInt();
            s.minTradeVolume = data[3].toInt();
            s.alpha = data[4].toInt();
            s.feeRatio = data[5].toInt();
            s.initialMarginRatio = data[6].toInt();
            s.maintenanceMarginRatio = data[7].toInt();
            s.startingPriceShiftLimit = data[8].toInt();
            s.isCloseOnly = data[9].toBool();
            s.lastTimestamp = data[10].toInt();
            s.lastIndexPrice = data[11].toInt();
            s.lastVolatility = data[12].toInt();
            s.netVolume = data[13].toInt();
            s.netCost = data[14].toInt();
            s.openVolume = data[15].toInt();
            s.tradersPnl = data[16].toInt();
            s.initialMarginRequired = data[17].toInt();
            s.cumulativeFundingPerVolume = data[18].toInt();
            s.lastNetVolume = data[19].toInt();
            s.lastNetVolumeBlock = data[20].toInt();
        }
    }

    function getAllSymbolStates() public view returns (IDLens.SymbolState[] memory ss) {
        bytes32[] memory symbolIds = symbolManager.getSymbolIds();
        ss = new IDLens.SymbolState[](symbolIds.length);
        for (uint256 i = 0; i < symbolIds.length; i++) {
            ss[i] = getSymbolState(symbolIds[i]);
        }
    }

    function getPosition(bytes32 symbolId, uint256 pTokenId) public view returns (IDLens.Position memory p) {
        p.symbol = getSymbol(symbolId);
        p.symbolId = symbolId;

        bytes32[] memory data = symbolManager.getPosition(symbolId, pTokenId);
        p.volume = data[0].toInt();
        p.cost = data[1].toInt();
        p.cumulativeFundingPerVolume = data[2].toInt();
    }

    function getPositionsOfPToken(uint256 pTokenId) public view returns (IDLens.Position[] memory pp) {
        bytes32[] memory symbolIds = symbolManager.getSymbolIdsOfPToken(pTokenId);
        pp = new IDLens.Position[](symbolIds.length);
        for (uint256 i = 0; i < symbolIds.length; i++) {
            pp[i] = getPosition(symbolIds[i], pTokenId);
        }
    }

}
