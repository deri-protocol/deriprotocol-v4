// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../../library/Bytes32.sol';
import '../../library/Bytes32Map.sol';
import '../../oracle/IOracle.sol';
import './ISymbolManager.sol';
import './ISymbol.sol';
import './IFutures.sol';
import './IOption.sol';
import './IPower.sol';
import './Futures.sol';
import './Option.sol';
import './Power.sol';
import './SymbolManagerStorage.sol';

contract SymbolManagerImplementation is SymbolManagerStorage {

    using Bytes32Map for mapping(uint8 => bytes32);
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    error OnlyEngine();
    error InvalidCategory(bytes32 symbolId, uint8 category);
    error ExistedSymbolId(bytes32 symbolId);
    error InvalidSymbolId(bytes32 symbolId);
    error InvalidTradeParams();
    error IndexPriceExpired();
    error VolatilityExpired();

    uint8 constant CATEGORY_FUTURES = 1;
    uint8 constant CATEGORY_OPTION  = 2;
    uint8 constant CATEGORY_POWER   = 3;

    address public immutable engine;
    address public immutable oracle;

    modifier _onlyEngine_() {
        if (msg.sender != engine) {
            revert OnlyEngine();
        }
        _;
    }

    constructor (address engine_, address oracle_) {
        engine = engine_;
        oracle = oracle_;
    }

    //================================================================================
    // Getters
    //================================================================================

    function getSymbolId(string memory symbol, uint8 category) public pure returns (bytes32 symbolId) {
        symbolId = Bytes32.toBytes32(symbol);
        symbolId |= bytes32(uint256(category));
    }

    function getCategory(bytes32 symbolId) public pure returns (uint8) {
        return uint8(uint256(symbolId));
    }

    function getSymbolIds() external view returns (bytes32[] memory) {
        return _symbolIds.values();
    }

    function getPTokenIdsOfSymbol(bytes32 symbolId) external view returns (uint256[] memory) {
        return _pTokenIds[symbolId].values();
    }

    function getSymbolIdsOfPToken(uint256 pTokenId) external view returns (bytes32[] memory) {
        return _tdSymbolIds[pTokenId].values();
    }

    function getState(bytes32 symbolId) external view returns (bytes32[] memory s) {
        mapping(uint8 => bytes32) storage state = _states[symbolId];
        uint8 category = getCategory(symbolId);
        if (category == CATEGORY_FUTURES) {
            s = Futures.getState(state);
        } else if (category == CATEGORY_OPTION) {
            s = Option.getState(state);
        } else if (category == CATEGORY_POWER) {
            s = Power.getState(state);
        }
    }

    function getPosition(bytes32 symbolId, uint256 pTokenId) external view returns (bytes32[] memory pos) {
        mapping(uint8 => bytes32) storage position = _positions[symbolId][pTokenId];
        uint8 category = getCategory(symbolId);
        if (category == CATEGORY_FUTURES) {
            pos = Futures.getPosition(position);
        } else if (category == CATEGORY_OPTION) {
            pos = Option.getPosition(position);
        } else if (category == CATEGORY_POWER) {
            pos = Power.getPosition(position);
        }
    }

    //================================================================================
    // Setters
    //================================================================================

    function addSymbol(string memory symbol, uint8 category, bytes32[] memory p) external _onlyAdmin_ {
        bytes32 symbolId = getSymbolId(symbol, category);
        if (_symbolIds.contains(symbolId)) {
            revert ExistedSymbolId(symbolId);
        }

        _symbolIds.add(symbolId);

        mapping(uint8 => bytes32) storage state = _states[symbolId];
        if (category == CATEGORY_FUTURES) {
            Futures.setParameter(symbolId, state, p);
        } else if (category == CATEGORY_OPTION) {
            Option.setParameter(symbolId, state, p);
        } else if (category == CATEGORY_POWER) {
            Power.setParameter(symbolId, state, p);
        } else {
            revert InvalidSymbolId(symbolId);
        }
    }

    function setParameterOfId(string memory symbol, uint8 category, uint8 parameterId, bytes32 value) external _onlyAdmin_ {
        bytes32 symbolId = getSymbolId(symbol, category);
        mapping(uint8 => bytes32) storage state = _states[symbolId];
        if (category == CATEGORY_FUTURES) {
            Futures.setParameterOfId(symbolId, state, parameterId, value);
        } else if (category == CATEGORY_OPTION) {
            Option.setParameterOfId(symbolId, state, parameterId, value);
        } else if (category == CATEGORY_POWER) {
            Power.setParameterOfId(symbolId, state, parameterId, value);
        } else {
            revert InvalidSymbolId(symbolId);
        }
    }

    function setParameterOfIdForCategory(uint8 category, uint8 parameterId, bytes32 value) external _onlyAdmin_ {
        uint256 length = _symbolIds.length();
        for (uint256 i = 0; i < length; i++) {
            bytes32 symbolId = _symbolIds.at(i);
            if (getCategory(symbolId) == category) {
                mapping(uint8 => bytes32) storage state = _states[symbolId];
                if (category == CATEGORY_FUTURES) {
                    Futures.setParameterOfId(symbolId, state, parameterId, value);
                } else if (category == CATEGORY_OPTION) {
                    Option.setParameterOfId(symbolId, state, parameterId, value);
                } else if (category == CATEGORY_POWER) {
                    Power.setParameterOfId(symbolId, state, parameterId, value);
                } else {
                    revert InvalidSymbolId(symbolId);
                }
            }
        }
    }

    //================================================================================
    // Settlers
    //================================================================================

    function settleSymbolsOnAddLiquidity(int256 liquidity)
    external _onlyEngine_ returns (ISymbolManager.SettlementOnAddLiquidity memory ss)
    {
        int256 diffInitialMarginRequired;
        uint256 length = _symbolIds.length();

        for (uint256 i = 0; i < length; i++) {
            ISymbol.SettlementOnAddLiquidity memory s = _settleOnAddLiquidity(
                _symbolIds.at(i), liquidity
            );
            if (s.settled) {
                ss.funding += s.funding;
                ss.diffTradersPnl += s.diffTradersPnl;
                diffInitialMarginRequired += s.diffInitialMarginRequired;
            }
        }

        initialMarginRequired += diffInitialMarginRequired;
    }

    function settleSymbolsOnRemoveLiquidity(int256 liquidity, int256 removedLiquidity)
    external _onlyEngine_ returns (ISymbolManager.SettlementOnRemoveLiquidity memory ss)
    {
        int256 diffInitialMarginRequired;
        uint256 length = _symbolIds.length();

        for (uint256 i = 0; i < length; i++) {
            ISymbol.SettlementOnRemoveLiquidity memory s = _settleOnRemoveLiquidity(
                _symbolIds.at(i), liquidity, removedLiquidity
            );
            if (s.settled) {
                ss.funding += s.funding;
                ss.diffTradersPnl += s.diffTradersPnl;
                ss.removeLiquidityPenalty += s.removeLiquidityPenalty;
                diffInitialMarginRequired += s.diffInitialMarginRequired;
            }
        }

        initialMarginRequired += diffInitialMarginRequired;
        ss.initialMarginRequired = initialMarginRequired;
    }

    function settleSymbolsOnRemoveMargin(uint256 pTokenId, int256 liquidity)
    external _onlyEngine_ returns (ISymbolManager.SettlementOnRemoveMargin memory ss)
    {
        int256 diffInitialMarginRequired;
        uint256 length = _tdSymbolIds[pTokenId].length();

        for (uint256 i = 0; i < length; i++) {
            ISymbol.SettlementOnTraderWithPosition memory s = _settleOnTraderWithPosition(
                _tdSymbolIds[pTokenId].at(i), pTokenId, liquidity
            );
            ss.funding += s.funding;
            ss.diffTradersPnl += s.diffTradersPnl;
            diffInitialMarginRequired += s.diffInitialMarginRequired;
            ss.traderFunding += s.traderFunding;
            ss.traderPnl += s.traderPnl;
            ss.traderInitialMarginRequired += s.traderInitialMarginRequired;
        }

        initialMarginRequired += diffInitialMarginRequired;
    }

    function settleSymbolsOnTrade(bytes32 symbolId, uint256 pTokenId, int256 liquidity, int256[] memory tradeParams)
    external _onlyEngine_ returns (ISymbolManager.SettlementOnTrade memory ss)
    {
        int256 diffInitialMarginRequired;
        uint256 length = _tdSymbolIds[pTokenId].length();

        for (uint256 i = 0; i < length; i++) {
            bytes32 symid = _tdSymbolIds[pTokenId].at(i);
            if (symid != symbolId) {
                ISymbol.SettlementOnTraderWithPosition memory s1 = _settleOnTraderWithPosition(
                    symid, pTokenId, liquidity
                );
                ss.funding += s1.funding;
                ss.diffTradersPnl += s1.diffTradersPnl;
                diffInitialMarginRequired += s1.diffInitialMarginRequired;
                ss.traderFunding += s1.traderFunding;
                ss.traderPnl += s1.traderPnl;
                ss.traderInitialMarginRequired += s1.traderInitialMarginRequired;
            }
        }

        ISymbol.SettlementOnTrade memory s2 = _settleOnTrade(
            symbolId, pTokenId, liquidity, tradeParams
        );

        ss.funding += s2.funding;
        ss.diffTradersPnl += s2.diffTradersPnl;
        diffInitialMarginRequired += s2.diffInitialMarginRequired;

        ss.traderFunding += s2.traderFunding;
        ss.traderPnl += s2.traderPnl;
        ss.traderInitialMarginRequired += s2.traderInitialMarginRequired;

        ss.tradeFee = s2.tradeFee;
        ss.tradeRealizedCost = s2.tradeRealizedCost;

        initialMarginRequired += diffInitialMarginRequired;
        ss.initialMarginRequired = initialMarginRequired;

        if (s2.positionChange == 1) {
            _pTokenIds[symbolId].add(pTokenId);
            _tdSymbolIds[pTokenId].add(symbolId);
        } else if (s2.positionChange == -1) {
            _pTokenIds[symbolId].remove(pTokenId);
            _tdSymbolIds[pTokenId].remove(symbolId);
        }
    }

    function settleSymbolsOnLiquidate(uint256 pTokenId, int256 liquidity)
    external _onlyEngine_ returns (ISymbolManager.SettlementOnLiquidate memory ss)
    {
        int256 diffInitialMarginRequired;
        uint256 length = _tdSymbolIds[pTokenId].length();

        // Pop EnumerableSet `_tdSymbolIds` backwards without messing up index during process
        for (uint256 i = length; i > 0; i--) {
            bytes32 symbolId = _tdSymbolIds[pTokenId].at(i-1);
            ISymbol.SettlementOnLiquidate memory s = _settleOnLiquidate(
                symbolId, pTokenId, liquidity
            );
            ss.funding += s.funding;
            ss.diffTradersPnl += s.diffTradersPnl;
            diffInitialMarginRequired += s.diffInitialMarginRequired;
            ss.traderFunding += s.traderFunding;
            ss.traderPnl += s.traderPnl;
            ss.traderMaintenanceMarginRequired += s.traderMaintenanceMarginRequired;
            ss.tradeRealizedCost += s.tradeRealizedCost;

            _pTokenIds[symbolId].remove(pTokenId);
            _tdSymbolIds[pTokenId].remove(symbolId);
        }

        initialMarginRequired += diffInitialMarginRequired;
    }

    //================================================================================
    // Internals
    //================================================================================

    function _checkCategory(bytes32 symbolId, uint8 category) internal pure {
        if (getCategory(symbolId) != category) {
            revert InvalidCategory(symbolId, category);
        }
    }

    function _getIndexPrice(bytes32 symbolId) internal view returns (int256) {
        mapping(uint8 => bytes32) storage state = _states[symbolId];
        uint8 category = getCategory(symbolId);
        bytes32 oracleId = (
            category == CATEGORY_FUTURES ? state.getBytes32(Futures.S_PRICEID) : (
            category == CATEGORY_OPTION  ? state.getBytes32(Option.S_PRICEID)  : (
            category == CATEGORY_POWER   ? state.getBytes32(Power.S_PRICEID)   :
            bytes32(0)
        )));
        return IOracle(oracle).getValueCurrentBlock(oracleId);
    }

    function _getVolatility(bytes32 symbolId) internal view returns (int256) {
        mapping(uint8 => bytes32) storage state = _states[symbolId];
        uint8 category = getCategory(symbolId);
        bytes32 oracleId = (
            category == CATEGORY_OPTION ? state.getBytes32(Option.S_VOLATILITYID) : (
            category == CATEGORY_POWER  ? state.getBytes32(Power.S_VOLATILITYID)  :
            bytes32(0)
        ));
        return IOracle(oracle).getValueCurrentBlock(oracleId);
    }

    function _settleOnAddLiquidity(bytes32 symbolId, int256 liquidity)
    internal returns (ISymbol.SettlementOnAddLiquidity memory s)
    {
        uint8 category = getCategory(symbolId);

        if (category == CATEGORY_FUTURES) {
            s = Futures.settleOnAddLiquidity(
                _states[symbolId],
                IFutures.VarOnAddLiquidity(
                    symbolId,
                    _getIndexPrice(symbolId),
                    liquidity
                )
            );
        } else if (category == CATEGORY_OPTION) {
            s = Option.settleOnAddLiquidity(
                _states[symbolId],
                IOption.VarOnAddLiquidity(
                    symbolId,
                    _getIndexPrice(symbolId),
                    _getVolatility(symbolId),
                    liquidity
                )
            );
        } else if (category == CATEGORY_POWER) {
            s = Power.settleOnAddLiquidity(
                _states[symbolId],
                IPower.VarOnAddLiquidity(
                    symbolId,
                    _getIndexPrice(symbolId),
                    _getVolatility(symbolId),
                    liquidity
                )
            );
        }
    }

    function _settleOnRemoveLiquidity(bytes32 symbolId, int256 liquidity, int256 removedLiquidity)
    internal returns (ISymbol.SettlementOnRemoveLiquidity memory s)
    {
        uint8 category = getCategory(symbolId);

        if (category == CATEGORY_FUTURES) {
            s = Futures.settleOnRemoveLiquidity(
                _states[symbolId],
                IFutures.VarOnRemoveLiquidity(
                    symbolId,
                    _getIndexPrice(symbolId),
                    liquidity,
                    removedLiquidity
                )
            );
        } else if (category == CATEGORY_OPTION) {
            s = Option.settleOnRemoveLiquidity(
                _states[symbolId],
                IOption.VarOnRemoveLiquidity(
                    symbolId,
                    _getIndexPrice(symbolId),
                    _getVolatility(symbolId),
                    liquidity,
                    removedLiquidity
                )
            );
        } else if (category == CATEGORY_POWER) {
            s = Power.settleOnRemoveLiquidity(
                _states[symbolId],
                IPower.VarOnRemoveLiquidity(
                    symbolId,
                    _getIndexPrice(symbolId),
                    _getVolatility(symbolId),
                    liquidity,
                    removedLiquidity
                )
            );
        }
    }

    function _settleOnTraderWithPosition(bytes32 symbolId, uint256 pTokenId, int256 liquidity)
    internal returns (ISymbol.SettlementOnTraderWithPosition memory s)
    {
        uint8 category = getCategory(symbolId);

        if (category == CATEGORY_FUTURES) {
            s = Futures.settleOnTraderWithPosition(
                _states[symbolId],
                _positions[symbolId][pTokenId],
                IFutures.VarOnTraderWithPosition(
                    symbolId,
                    pTokenId,
                    _getIndexPrice(symbolId),
                    liquidity
                )
            );
        } else if (category == CATEGORY_OPTION) {
            s = Option.settleOnTraderWithPosition(
                _states[symbolId],
                _positions[symbolId][pTokenId],
                IOption.VarOnTraderWithPosition(
                    symbolId,
                    pTokenId,
                    _getIndexPrice(symbolId),
                    _getVolatility(symbolId),
                    liquidity
                )
            );
        } else if (category == CATEGORY_POWER) {
            s = Power.settleOnTraderWithPosition(
                _states[symbolId],
                _positions[symbolId][pTokenId],
                IPower.VarOnTraderWithPosition(
                    symbolId,
                    pTokenId,
                    _getIndexPrice(symbolId),
                    _getVolatility(symbolId),
                    liquidity
                )
            );
        }
    }

    function _checkTradeParamsLength(uint256 provided, uint256 expected) internal pure {
        if (provided != expected) {
            revert InvalidTradeParams();
        }
    }

    function _settleOnTrade(bytes32 symbolId, uint256 pTokenId, int256 liquidity, int256[] memory tradeParams)
    internal returns (ISymbol.SettlementOnTrade memory s)
    {
        uint8 category = getCategory(symbolId);

        if (category == CATEGORY_FUTURES) {
            _checkTradeParamsLength(tradeParams.length, 2);
            s = Futures.settleOnTrade(
                _states[symbolId],
                _positions[symbolId][pTokenId],
                IFutures.VarOnTrade(
                    symbolId,
                    pTokenId,
                    _getIndexPrice(symbolId),
                    liquidity,
                    tradeParams[0], // tradeVolume
                    tradeParams[1]  // priceLimit
                )
            );
        } else if (category == CATEGORY_OPTION) {
            _checkTradeParamsLength(tradeParams.length, 2);
            s = Option.settleOnTrade(
                _states[symbolId],
                _positions[symbolId][pTokenId],
                IOption.VarOnTrade(
                    symbolId,
                    pTokenId,
                    _getIndexPrice(symbolId),
                    _getVolatility(symbolId),
                    liquidity,
                    tradeParams[0], // tradeVolume
                    tradeParams[1]  // priceLimit
                )
            );
        } else if (category == CATEGORY_POWER) {
            _checkTradeParamsLength(tradeParams.length, 2);
            s = Power.settleOnTrade(
                _states[symbolId],
                _positions[symbolId][pTokenId],
                IPower.VarOnTrade(
                    symbolId,
                    pTokenId,
                    _getIndexPrice(symbolId),
                    _getVolatility(symbolId),
                    liquidity,
                    tradeParams[0], // tradeVolume
                    tradeParams[1]  // priceLimit
                )
            );
        }
    }

    function _settleOnLiquidate(bytes32 symbolId, uint256 pTokenId, int256 liquidity)
    internal returns (ISymbol.SettlementOnLiquidate memory s)
    {
        uint8 category = getCategory(symbolId);

        if (category == CATEGORY_FUTURES) {
            s = Futures.settleOnLiquidate(
                _states[symbolId],
                _positions[symbolId][pTokenId],
                IFutures.VarOnLiquidate(
                    symbolId,
                    pTokenId,
                    _getIndexPrice(symbolId),
                    liquidity
                )
            );
        } else if (category == CATEGORY_OPTION) {
            s = Option.settleOnLiquidate(
                _states[symbolId],
                _positions[symbolId][pTokenId],
                IOption.VarOnLiquidate(
                    symbolId,
                    pTokenId,
                    _getIndexPrice(symbolId),
                    _getVolatility(symbolId),
                    liquidity
                )
            );
        } else if (category == CATEGORY_POWER) {
            s = Power.settleOnLiquidate(
                _states[symbolId],
                _positions[symbolId][pTokenId],
                IPower.VarOnLiquidate(
                    symbolId,
                    pTokenId,
                    _getIndexPrice(symbolId),
                    _getVolatility(symbolId),
                    liquidity
                )
            );
        }
    }

}
