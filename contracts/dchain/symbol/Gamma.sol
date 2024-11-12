// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './IGamma.sol';
import '../../library/SafeMath.sol';
import '../../library/Bytes32Map.sol';
import '../../library/DpmmFutures.sol';
import '../../library/DpmmPower.sol';

library Gamma {

    using Bytes32Map for mapping(uint8 => bytes32);
    using SafeMath for uint256;
    using SafeMath for int256;

    error WrongParameterLength();
    error InvalidTradeVolume();
    error CloseOnly();
    error SlippageExceedsLimit();
    error MarkExceedsLimit();
    error NoVolumeToForceClose();

    event UpdateGammaParameter(bytes32 symbolId);
    event RemoveGamma(bytes32 symbolId);
    event SettleGammaOnAddLiquidity(
        bytes32 indexed symbolId,
        IGamma.EventDataOnAddLiquidity data
    );
    event SettleGammaOnRemoveLiquidity(
        bytes32 indexed symbolId,
        IGamma.EventDataOnRemoveLiquidity data
    );
    event SettleGammaOnTraderWithPosition(
        bytes32 indexed symbolId,
        uint256 indexed pTokenId,
        IGamma.EventDataOnTraderWithPosition data
    );
    event SettleGammaOnTrade(
        bytes32 indexed symbolId,
        uint256 indexed pTokenId,
        IGamma.EventDataOnTrade data
    );
    event SettleGammaOnLiquidate(
        bytes32 indexed symbolId,
        uint256 indexed pTokenId,
        IGamma.EventDataOnLiquidate data
    );
    event SettleGammaOnForceClose(
        bytes32 indexed symbolId,
        uint256 indexed pTokenId,
        IGamma.EventDataOnForceClose data
    );

    // parameters
    uint8 constant S_PRICEID                 = 1;
    uint8 constant S_VOLATILITYID            = 2;
    uint8 constant S_FUNDINGPERIOD           = 3;
    uint8 constant S_MINTRADEVOLUME          = 4;
    uint8 constant S_POWERALPHA              = 5;
    uint8 constant S_FUTURESALPHA            = 6;
    uint8 constant S_POWERFEERATIO           = 7;
    uint8 constant S_FUTURESFEERATIO         = 8;
    uint8 constant S_INITIALMARGINRATIO      = 9;
    uint8 constant S_MAINTENANCEMARGINRATIO  = 10;
    uint8 constant S_ISCLOSEONLY             = 11;

    // states
    uint8 constant S_LASTTIMESTAMP                         = 101;
    uint8 constant S_LASTINDEXPRICE                        = 102;
    uint8 constant S_LASTVOLATILITY                        = 103;
    uint8 constant S_NETPOWERVOLUME                        = 104;
    uint8 constant S_NETREALFUTURESVOLUME                  = 105;
    uint8 constant S_NETCOST                               = 106;
    uint8 constant S_TRADERSPNL                            = 107;
    uint8 constant S_INITIALMARGINREQUIRED                 = 108;
    uint8 constant S_CUMULAITVEFUNDINGPERPOWERVOLUME       = 109;
    uint8 constant S_CUMULATIVEFUNDINGPERREALFUTURESVOLUME = 110;

    uint8 constant P_POWERVOLUME                           = 1;
    uint8 constant P_REALFUTURESVOLUME                     = 2;
    uint8 constant P_COST                                  = 3;
    uint8 constant P_CUMULAITVEFUNDINGPERPOWERVOLUME       = 4;
    uint8 constant P_CUMULATIVEFUNDINGPERREALFUTURESVOLUME = 5;

    // uint8 constant ACTION_ADDLIQUIDITY      = 1;
    // uint8 constant ACTION_REMOVELIQUIDITY   = 2;
    // uint8 constant ACTION_TRADERWITHPOSTION = 3;
    // uint8 constant ACTION_TRADE             = 4;
    // uint8 constant ACTION_LIQUIDATE         = 5;

    int256 constant ONE = 1e18;
    int256 constant r = 109500000000000000; // risk-free interest rate

    //================================================================================
    // Getters
    //================================================================================

    function getState(mapping(uint8 => bytes32) storage state)
    external view returns (bytes32[] memory s)
    {
        s = new bytes32[](21);

        s[0]  = state.getBytes32(S_PRICEID);
        s[1]  = state.getBytes32(S_VOLATILITYID);
        s[2]  = state.getBytes32(S_FUNDINGPERIOD);
        s[3]  = state.getBytes32(S_MINTRADEVOLUME);
        s[4]  = state.getBytes32(S_POWERALPHA);
        s[5]  = state.getBytes32(S_FUTURESALPHA);
        s[6]  = state.getBytes32(S_POWERFEERATIO);
        s[7]  = state.getBytes32(S_FUTURESFEERATIO);
        s[8]  = state.getBytes32(S_INITIALMARGINRATIO);
        s[9]  = state.getBytes32(S_MAINTENANCEMARGINRATIO);
        s[10] = state.getBytes32(S_ISCLOSEONLY);

        s[11] = state.getBytes32(S_LASTTIMESTAMP);
        s[12] = state.getBytes32(S_LASTINDEXPRICE);
        s[13] = state.getBytes32(S_LASTVOLATILITY);
        s[14] = state.getBytes32(S_NETPOWERVOLUME);
        s[15] = state.getBytes32(S_NETREALFUTURESVOLUME);
        s[16] = state.getBytes32(S_NETCOST);
        s[17] = state.getBytes32(S_TRADERSPNL);
        s[18] = state.getBytes32(S_INITIALMARGINREQUIRED);
        s[19] = state.getBytes32(S_CUMULAITVEFUNDINGPERPOWERVOLUME);
        s[20] = state.getBytes32(S_CUMULATIVEFUNDINGPERREALFUTURESVOLUME);
    }

    function getPosition(mapping(uint8 => bytes32) storage position)
    external view returns (bytes32[] memory pos)
    {
        pos = new bytes32[](5);
        pos[0] = position.getBytes32(P_POWERVOLUME);
        pos[1] = position.getBytes32(P_REALFUTURESVOLUME);
        pos[2] = position.getBytes32(P_COST);
        pos[3] = position.getBytes32(P_CUMULAITVEFUNDINGPERPOWERVOLUME);
        pos[4] = position.getBytes32(P_CUMULATIVEFUNDINGPERREALFUTURESVOLUME);
    }


    //================================================================================
    // Setters
    //================================================================================

    function setParameter(
        bytes32 symbolId,
        mapping(uint8 => bytes32) storage state,
        bytes32[] memory p
    ) external {
        if (p.length != 11) {
            revert WrongParameterLength();
        }
        state.set(S_PRICEID, p[0]);
        state.set(S_VOLATILITYID, p[1]);
        state.set(S_FUNDINGPERIOD, p[2]);
        state.set(S_MINTRADEVOLUME, p[3]);
        state.set(S_POWERALPHA, p[4]);
        state.set(S_FUTURESALPHA, p[5]);
        state.set(S_POWERFEERATIO, p[6]);
        state.set(S_FUTURESFEERATIO, p[7]);
        state.set(S_INITIALMARGINRATIO, p[8]);
        state.set(S_MAINTENANCEMARGINRATIO, p[9]);
        state.set(S_ISCLOSEONLY, p[10]);
        emit UpdateGammaParameter(symbolId);
    }

    function setParameterOfId(
        bytes32 symbolId,
        mapping(uint8 => bytes32) storage state,
        uint8 parameterId,
        bytes32 value
    ) external {
        state.set(parameterId, value);
        emit UpdateGammaParameter(symbolId);
    }

    function removeSymbol(bytes32 symbolId, mapping(uint8 => bytes32) storage state) external {
        require(
            state.getInt(S_NETPOWERVOLUME) == 0 &&
            state.getInt(S_NETREALFUTURESVOLUME) == 0 &&
            state.getInt(S_NETCOST) == 0 &&
            state.getInt(S_INITIALMARGINREQUIRED) == 0,
            'Have position'
        );
        state.set(S_PRICEID, bytes32(0));
        state.set(S_VOLATILITYID, bytes32(0));
        state.set(S_FUNDINGPERIOD, bytes32(0));
        state.set(S_MINTRADEVOLUME, bytes32(0));
        state.set(S_POWERALPHA, bytes32(0));
        state.set(S_FUTURESALPHA, bytes32(0));
        state.set(S_POWERFEERATIO, bytes32(0));
        state.set(S_FUTURESFEERATIO, bytes32(0));
        state.set(S_INITIALMARGINRATIO, bytes32(0));
        state.set(S_MAINTENANCEMARGINRATIO, bytes32(0));
        state.set(S_ISCLOSEONLY, true);
        emit RemoveGamma(symbolId);
    }

    //================================================================================
    // Settlers
    //================================================================================

    function settleOnAddLiquidity(
        mapping(uint8 => bytes32) storage state,
        IGamma.VarOnAddLiquidity memory v
    ) external returns (IGamma.SettlementOnAddLiquidity memory s)
    {
        Data memory data = _getData(state, v.indexPrice, v.volatility);
        _getFunding(data, v.liquidity);
        _getTradersPnl(data);
        _getInitialMarginRequired(data);

        s.settled = true;
        s.funding = data.funding;
        s.diffTradersPnl = data.tradersPnl - state.getInt(S_TRADERSPNL);
        s.diffInitialMarginRequired = data.initialMarginRequired - state.getInt(S_INITIALMARGINREQUIRED);

        _saveData(state, data, false);

        emit SettleGammaOnAddLiquidity(v.symbolId, IGamma.EventDataOnAddLiquidity({
            indexPrice: v.indexPrice,
            volatility: v.volatility,
            liquidity: v.liquidity,
            funding: data.funding,
            tradersPnl: data.tradersPnl,
            initialMarginRequired: data.initialMarginRequired
        }));
    }

    function settleOnRemoveLiquidity(
        mapping(uint8 => bytes32) storage state,
        IGamma.VarOnRemoveLiquidity memory v
    ) external returns (IGamma.SettlementOnRemoveLiquidity memory s)
    {
        Data memory data = _getData(state, v.indexPrice, v.volatility);
        _getFunding(data, v.liquidity);
        _getTradersPnl(data);
        _getInitialMarginRequired(data);
        _getRemoveLiquidityPenalty(data, v.liquidity, v.removedLiquidity);

        s.settled = true;
        s.funding = data.funding;
        s.diffTradersPnl = data.tradersPnl - state.getInt(S_TRADERSPNL);
        s.diffInitialMarginRequired = data.initialMarginRequired - state.getInt(S_INITIALMARGINREQUIRED);
        s.removeLiquidityPenalty = data.removeLiquidityPenalty;

        _saveData(state, data, false);

        emit SettleGammaOnRemoveLiquidity(v.symbolId, IGamma.EventDataOnRemoveLiquidity({
            indexPrice: v.indexPrice,
            volatility: v.volatility,
            liquidity: v.liquidity,
            removedLiquidity: v.removedLiquidity,
            funding: data.funding,
            tradersPnl: data.tradersPnl,
            initialMarginRequired: data.initialMarginRequired,
            removeLiquidityPenalty: data.removeLiquidityPenalty
        }));
    }

    function settleOnTraderWithPosition(
        mapping(uint8 => bytes32) storage state,
        mapping(uint8 => bytes32) storage position,
        IGamma.VarOnTraderWithPosition memory v
    ) external returns (IGamma.SettlementOnTraderWithPosition memory s)
    {
        Data memory data = _getDataWithPosition(state, position, v.indexPrice, v.volatility);
        _getFunding(data, v.liquidity);
        _getTradersPnl(data);
        _getInitialMarginRequired(data);

        s.funding = data.funding;
        s.diffTradersPnl = data.tradersPnl - state.getInt(S_TRADERSPNL);
        s.diffInitialMarginRequired = data.initialMarginRequired - state.getInt(S_INITIALMARGINREQUIRED);

        {
            int256 diff;
            unchecked { diff = data.cumulaitveFundingPerPowerVolume - data.tdCumulaitveFundingPerPowerVolume; }
            s.traderFunding = data.tdPowerVolume * diff / ONE;
            unchecked { diff = data.cumulativeFundingPerRealFuturesVolume - data.tdCumulativeFundingPerRealFuturesVolume; }
            s.traderFunding += data.tdRealFuturesVolume * diff / ONE;
        }

        s.traderPnl = _calculateTraderPnl(data);
        s.traderInitialMarginRequired = _calculateInitialMarginRequired(
            data.curIndexPrice,
            data.oneHT,
            data.tdPowerVolume,
            data.tdRealFuturesVolume,
            data.initialMarginRatio
        );

        _saveData(state, data, false);
        position.set(P_CUMULAITVEFUNDINGPERPOWERVOLUME, data.cumulaitveFundingPerPowerVolume);
        position.set(P_CUMULATIVEFUNDINGPERREALFUTURESVOLUME, data.cumulativeFundingPerRealFuturesVolume);

        emit SettleGammaOnTraderWithPosition(v.symbolId, v.pTokenId, IGamma.EventDataOnTraderWithPosition({
            indexPrice: v.indexPrice,
            volatility: v.volatility,
            liquidity: v.liquidity,
            funding: data.funding,
            tradersPnl: data.tradersPnl,
            initialMarginRequired: data.initialMarginRequired,
            traderFunding: s.traderFunding,
            traderPnl: s.traderPnl,
            traderInitialMarginRequired: s.traderInitialMarginRequired
        }));
    }

    struct TempTrade {
        bool isOpen;
        int256 diff;
        int256 powerCost;
        int256 realFuturesVolume;
        int256 realFuturesCost;
        int256 effectiveFuturesVolume;
        int256 effectiveFuturesCost;
        int256 slippageCost;
    }

    function settleOnTrade(
        mapping(uint8 => bytes32) storage state,
        mapping(uint8 => bytes32) storage position,
        IGamma.VarOnTrade memory v
    ) external returns (IGamma.SettlementOnTrade memory s)
    {
        if (v.tradeVolume == 0 || v.tradeVolume % state.getInt(S_MINTRADEVOLUME) != 0) {
            revert InvalidTradeVolume();
        }

        Data memory data = _getDataWithPosition(state, position, v.indexPrice, v.volatility);
        TempTrade memory temp;

        temp.isOpen = data.tdPowerVolume * v.tradeVolume >= 0;
        if (!temp.isOpen) {
            if (v.tradeVolume.abs() > data.tdPowerVolume.abs()) {
                revert InvalidTradeVolume();
            }
        } else {
            if (state.getBool(S_ISCLOSEONLY)) {
                revert CloseOnly();
            }
        }

        _getFunding(data, v.liquidity);

        // funding
        unchecked { temp.diff = data.cumulaitveFundingPerPowerVolume - data.tdCumulaitveFundingPerPowerVolume; }
        s.traderFunding = data.tdPowerVolume * temp.diff / ONE;
        unchecked { temp.diff = data.cumulativeFundingPerRealFuturesVolume - data.tdCumulativeFundingPerRealFuturesVolume; }
        s.traderFunding += data.tdRealFuturesVolume * temp.diff / ONE;

        // trade
        if (v.entryPrice <= 0) v.entryPrice = data.curIndexPrice;
        // power cost calculated through power's DPMM, with power's slippage cost included
        temp.powerCost = DpmmPower.calculateCost(
            data.powerTheoreticalPrice, data.powerK, data.netPowerVolume, v.tradeVolume
        );
        temp.realFuturesVolume = temp.isOpen
                               ? -2 * v.entryPrice * v.tradeVolume / data.oneHT
                               : -data.tdRealFuturesVolume * v.tradeVolume.abs() / data.tdPowerVolume.abs();
        // real futures' cost, without slippage
        temp.realFuturesCost = temp.realFuturesVolume * data.curIndexPrice / ONE;
        temp.effectiveFuturesVolume = 2 * data.curIndexPrice * v.tradeVolume / data.oneHT + temp.realFuturesVolume;
        temp.effectiveFuturesCost = DpmmFutures.calculateCost(
            data.curIndexPrice, data.futuresK, data.curNetEffectiveFuturesVolume, temp.effectiveFuturesVolume
        );
        // calculate effective futures' slippage cost in effective futures' DPMM
        // this slippage cost combined with real futures' cost is the final cost on futures part
        temp.slippageCost = _calculateSlippageCost(
            data.curIndexPrice, data.futuresK, data.curNetEffectiveFuturesVolume, temp.effectiveFuturesVolume
        );

        // total cost consists with 3 parts: power's cost, real futures' cost without slippage, effective futures' slippage cost
        s.tradeCost = temp.powerCost + temp.realFuturesCost + temp.slippageCost;
        // fee depends on power cost and effective futures cost
        s.tradeFee = (
            temp.powerCost.abs() * state.getInt(S_POWERFEERATIO) +
            temp.effectiveFuturesCost.abs() * state.getInt(S_FUTURESFEERATIO)
        ) / ONE;

        // check slippage
        // if tradeVolume > 0, powerCost / tradeVolume <= powerPriceLimit
        // if tradeVolume < 0, powerCost / tradeVolume >= powerPriceLimit
        if (temp.powerCost * ONE > v.powerPriceLimit * v.tradeVolume) {
            revert SlippageExceedsLimit();
        }

        // if effectiveFuturesVolume > 0, slippageCost / effectiveFuturesVolume + curIndexPrice <= futuresPriceLimit
        // if effectiveFuturesVolume < 0, slippageCost / effectiveFuturesVolume + curIndexPrice >= futuresPriceLimit
        if (temp.effectiveFuturesVolume != 0) {
            if (
                temp.slippageCost * ONE + data.curIndexPrice * temp.effectiveFuturesVolume
                > v.futuresPriceLimit * temp.effectiveFuturesVolume
            ) {
                revert SlippageExceedsLimit();
            }
        }

        if (!temp.isOpen) {
            s.tradeRealizedCost = data.tdCost * v.tradeVolume.abs() / data.tdPowerVolume.abs() + s.tradeCost;
        }

        data.netPowerVolume += v.tradeVolume;
        data.netRealFuturesVolume += temp.realFuturesVolume;
        data.curNetEffectiveFuturesVolume += temp.effectiveFuturesVolume;
        data.netCost += s.tradeCost - s.tradeRealizedCost;
        _getTradersPnl(data);
        _getInitialMarginRequired(data);

        if (
            (DpmmPower.calculateMarkPrice(data.powerTheoreticalPrice, data.powerK, data.netPowerVolume) <= 0) ||
            (DpmmFutures.calculateMarkPrice(data.curIndexPrice, data.futuresK, data.curNetEffectiveFuturesVolume) <= 0)
        ) {
            revert MarkExceedsLimit();
        }

        if (data.tdPowerVolume == 0) {
            s.positionChange = 1;
        } else if (data.tdPowerVolume + v.tradeVolume == 0) {
            s.positionChange = -1;
        } else {
            int256 volume1 = data.tdPowerVolume;
            int256 volume2 = data.tdPowerVolume + v.tradeVolume;
            if (volume1 > 0 && volume2 > 0 || volume1 < 0 && volume2 < 0) {
                if (volume2.abs() > volume1.abs()) {
                    s.positionChange = 2;
                } else {
                    s.positionChange = -2;
                }
            }
        }

        data.tdPowerVolume += v.tradeVolume;
        data.tdRealFuturesVolume += temp.realFuturesVolume;
        // If A's position cost is 1000, and A's close half of his position,
        // Assume the tradeCost is -600, then A's realizedCost is 1000 / 2 + -600 = -100, i.e. PNL = 100
        // And the remained position cost will be 500
        // Which is calculated as: 500 = 1000 + (-600) - (-100)
        data.tdCost += s.tradeCost - s.tradeRealizedCost;
        data.tdCumulaitveFundingPerPowerVolume = data.cumulaitveFundingPerPowerVolume;
        data.tdCumulativeFundingPerRealFuturesVolume = data.cumulativeFundingPerRealFuturesVolume;

        s.funding = data.funding;
        s.diffTradersPnl = data.tradersPnl - state.getInt(S_TRADERSPNL);
        s.diffInitialMarginRequired = data.initialMarginRequired - state.getInt(S_INITIALMARGINREQUIRED);

        s.traderPnl = _calculateTraderPnl(data);
        s.traderInitialMarginRequired = _calculateInitialMarginRequired(
            data.curIndexPrice,
            data.oneHT,
            data.tdPowerVolume,
            data.tdRealFuturesVolume,
            data.initialMarginRatio
        );

        _saveData(state, data, true);
        position.set(P_POWERVOLUME, data.tdPowerVolume);
        position.set(P_REALFUTURESVOLUME, data.tdRealFuturesVolume);
        position.set(P_COST, data.tdCost);
        position.set(P_CUMULAITVEFUNDINGPERPOWERVOLUME, data.tdCumulaitveFundingPerPowerVolume);
        position.set(P_CUMULATIVEFUNDINGPERREALFUTURESVOLUME, data.tdCumulativeFundingPerRealFuturesVolume);

        emit SettleGammaOnTrade(v.symbolId, v.pTokenId, IGamma.EventDataOnTrade({
            indexPrice: v.indexPrice,
            volatility: v.volatility,
            liquidity: v.liquidity,
            tradeVolume: v.tradeVolume,
            funding: data.funding,
            tradersPnl: data.tradersPnl,
            initialMarginRequired: data.initialMarginRequired,
            traderFunding: s.traderFunding,
            traderPnl: s.traderPnl,
            traderInitialMarginRequired: s.traderInitialMarginRequired,
            tradeCost: s.tradeCost,
            tradeFee: s.tradeFee,
            tradeRealizedCost: s.tradeRealizedCost
        }));
    }

    function settleOnForceClose(
        mapping(uint8 => bytes32) storage state,
        mapping(uint8 => bytes32) storage position,
        IGamma.VarOnForceClose memory v
    ) external returns (IGamma.SettlementOnForceClose memory s)
    {
        Data memory data = _getDataWithPosition(state, position, v.indexPrice, v.volatility);
        TempTrade memory temp;

        if (data.tdPowerVolume == 0) {
            revert NoVolumeToForceClose();
        }

        _getFunding(data, v.liquidity);

        // funding
        unchecked { temp.diff = data.cumulaitveFundingPerPowerVolume - data.tdCumulaitveFundingPerPowerVolume; }
        s.traderFunding = data.tdPowerVolume * temp.diff / ONE;
        unchecked { temp.diff = data.cumulativeFundingPerRealFuturesVolume - data.tdCumulativeFundingPerRealFuturesVolume; }
        s.traderFunding += data.tdRealFuturesVolume * temp.diff / ONE;

        // trade
        int256 tradeVolume = -data.tdPowerVolume;
        temp.powerCost = DpmmPower.calculateCost(
            data.powerTheoreticalPrice, data.powerK, data.netPowerVolume, tradeVolume
        );
        temp.realFuturesVolume = -data.tdRealFuturesVolume;
        temp.realFuturesCost = temp.realFuturesVolume * data.curIndexPrice / ONE;
        temp.effectiveFuturesVolume = 2 * data.curIndexPrice * tradeVolume / data.oneHT + temp.realFuturesVolume;
        temp.slippageCost = _calculateSlippageCost(
            data.curIndexPrice, data.futuresK, data.curNetEffectiveFuturesVolume, temp.effectiveFuturesVolume
        );
        s.tradeCost = temp.powerCost + temp.realFuturesCost + temp.slippageCost;
        s.tradeRealizedCost = data.tdCost + s.tradeCost;

        data.netPowerVolume -= data.tdPowerVolume;
        data.netRealFuturesVolume -= data.tdRealFuturesVolume;
        data.netCost -= data.tdCost;
        _getTradersPnl(data);
        _getInitialMarginRequired(data);

        data.tdPowerVolume = 0;
        data.tdRealFuturesVolume = 0;
        data.tdCost = 0;
        data.tdCumulaitveFundingPerPowerVolume = data.cumulaitveFundingPerPowerVolume;
        data.tdCumulativeFundingPerRealFuturesVolume = data.cumulativeFundingPerRealFuturesVolume;

        s.funding = data.funding;
        s.diffTradersPnl = data.tradersPnl - state.getInt(S_TRADERSPNL);
        s.diffInitialMarginRequired = data.initialMarginRequired - state.getInt(S_INITIALMARGINREQUIRED);

        _saveData(state, data, true);
        position.set(P_POWERVOLUME, data.tdPowerVolume);
        position.set(P_REALFUTURESVOLUME, data.tdRealFuturesVolume);
        position.set(P_COST, data.tdCost);
        position.set(P_CUMULAITVEFUNDINGPERPOWERVOLUME, data.tdCumulaitveFundingPerPowerVolume);
        position.set(P_CUMULATIVEFUNDINGPERREALFUTURESVOLUME, data.tdCumulativeFundingPerRealFuturesVolume);

        emit SettleGammaOnForceClose(v.symbolId, v.pTokenId, IGamma.EventDataOnForceClose({
            indexPrice: v.indexPrice,
            volatility: v.volatility,
            liquidity: v.liquidity,
            tradeVolume: tradeVolume,
            funding: data.funding,
            tradersPnl: data.tradersPnl,
            initialMarginRequired: data.initialMarginRequired,
            traderFunding: s.traderFunding,
            tradeCost: s.tradeCost,
            tradeRealizedCost: s.tradeRealizedCost
        }));
    }

    function settleOnLiquidate(
        mapping(uint8 => bytes32) storage state,
        mapping(uint8 => bytes32) storage position,
        IGamma.VarOnLiquidate memory v
    ) external returns (IGamma.SettlementOnLiquidate memory s)
    {
        Data memory data = _getDataWithPosition(state, position, v.indexPrice, v.volatility);
        TempTrade memory temp;

        _getFunding(data, v.liquidity);

        // funding
        unchecked { temp.diff = data.cumulaitveFundingPerPowerVolume - data.tdCumulaitveFundingPerPowerVolume; }
        s.traderFunding = data.tdPowerVolume * temp.diff / ONE;
        unchecked { temp.diff = data.cumulativeFundingPerRealFuturesVolume - data.tdCumulativeFundingPerRealFuturesVolume; }
        s.traderFunding += data.tdRealFuturesVolume * temp.diff / ONE;

        // trade
        s.tradeVolume = -data.tdPowerVolume;
        temp.powerCost = DpmmPower.calculateCost(
            data.powerTheoreticalPrice, data.powerK, data.netPowerVolume, -data.tdPowerVolume
        );
        temp.realFuturesVolume = -data.tdRealFuturesVolume;
        temp.realFuturesCost = temp.realFuturesVolume * data.curIndexPrice / ONE;
        temp.effectiveFuturesVolume = -2 * data.curIndexPrice * data.tdPowerVolume / data.oneHT + temp.realFuturesVolume;
        temp.slippageCost = _calculateSlippageCost(
            data.curIndexPrice, data.futuresK, data.curNetEffectiveFuturesVolume, temp.effectiveFuturesVolume
        );

        s.tradeCost = temp.powerCost + temp.realFuturesCost + temp.slippageCost;
        s.tradeRealizedCost = s.tradeCost + data.tdCost;

        s.traderPnl = _calculateTraderPnl(data);
        int256 traderInitialMarginRequired = _calculateInitialMarginRequired(
            data.curIndexPrice,
            data.oneHT,
            data.tdPowerVolume,
            data.tdRealFuturesVolume,
            data.initialMarginRatio
        );
        s.traderMaintenanceMarginRequired = traderInitialMarginRequired * state.getInt(S_MAINTENANCEMARGINRATIO) / data.initialMarginRatio;

        data.netPowerVolume += -data.tdPowerVolume;
        data.netRealFuturesVolume += temp.realFuturesVolume;
        data.curNetEffectiveFuturesVolume += temp.effectiveFuturesVolume;
        data.netCost += s.tradeCost - s.tradeRealizedCost;
        _getTradersPnl(data);
        _getInitialMarginRequired(data);

        s.funding = data.funding;
        s.diffTradersPnl = data.tradersPnl - state.getInt(S_TRADERSPNL);
        s.diffInitialMarginRequired = data.initialMarginRequired - state.getInt(S_INITIALMARGINREQUIRED);

        _saveData(state, data, true);
        position.del(P_POWERVOLUME);
        position.del(P_REALFUTURESVOLUME);
        position.del(P_COST);
        position.del(P_CUMULAITVEFUNDINGPERPOWERVOLUME);
        position.del(P_CUMULATIVEFUNDINGPERREALFUTURESVOLUME);

        emit SettleGammaOnLiquidate(v.symbolId, v.pTokenId, IGamma.EventDataOnLiquidate({
            indexPrice: v.indexPrice,
            volatility: v.volatility,
            liquidity: v.liquidity,
            funding: data.funding,
            tradersPnl: data.tradersPnl,
            initialMarginRequired: data.initialMarginRequired,
            traderFunding: s.traderFunding,
            traderPnl: s.traderPnl,
            traderMaintenanceMarginRequired: s.traderMaintenanceMarginRequired,
            tradeVolume: s.tradeVolume,
            tradeCost: s.tradeCost,
            tradeRealizedCost: s.tradeRealizedCost
        }));
    }

    //================================================================================
    // Internals
    //================================================================================

    // Data struct holds temp values
    struct Data {
        // states
        uint256 preTimestamp;
        uint256 curTimestamp;
        int256 preIndexPrice;
        int256 curIndexPrice;
        int256 curVolatility;
        int256 netPowerVolume;
        int256 netRealFuturesVolume;
        int256 netCost;
        int256 cumulaitveFundingPerPowerVolume;
        int256 cumulativeFundingPerRealFuturesVolume;
        // parameters
        int256 fundingPeriod;
        int256 powerAlpha;
        int256 futuresAlpha;
        int256 initialMarginRatio;
        // postion
        int256 tdPowerVolume;
        int256 tdRealFuturesVolume;
        int256 tdCost;
        int256 tdCumulaitveFundingPerPowerVolume;
        int256 tdCumulativeFundingPerRealFuturesVolume;
        // calculations
        int256 oneHT;
        int256 powerTheoreticalPrice;
        int256 powerK;
        int256 futuresK;
        int256 preNetEffectiveFuturesVolume;
        int256 curNetEffectiveFuturesVolume;
        int256 funding;
        int256 tradersPnl;
        int256 initialMarginRequired;
        int256 removeLiquidityPenalty;
    }

    // settlement cannot be skipped even netPowerVolume == 0
    // Gamma doesn't have a _getDataWithSkip alternative
    function _getData(
        mapping(uint8 => bytes32) storage state,
        int256 curIndexPrice,
        int256 curVolatility
    ) internal view returns (Data memory data)
    {
        data.preTimestamp = state.getUint(S_LASTTIMESTAMP);
        data.curTimestamp = block.timestamp;
        data.preIndexPrice = state.getInt(S_LASTINDEXPRICE);
        data.curIndexPrice = curIndexPrice;
        data.curVolatility = curVolatility;
        data.netPowerVolume = state.getInt(S_NETPOWERVOLUME);
        data.netRealFuturesVolume = state.getInt(S_NETREALFUTURESVOLUME);
        data.netCost = state.getInt(S_NETCOST);
        data.cumulaitveFundingPerPowerVolume = state.getInt(S_CUMULAITVEFUNDINGPERPOWERVOLUME);
        data.cumulativeFundingPerRealFuturesVolume = state.getInt(S_CUMULATIVEFUNDINGPERREALFUTURESVOLUME);

        data.fundingPeriod = state.getInt(S_FUNDINGPERIOD);
        data.powerAlpha = state.getInt(S_POWERALPHA);
        data.futuresAlpha = state.getInt(S_FUTURESALPHA);
        data.initialMarginRatio = state.getInt(S_INITIALMARGINRATIO);
    }

    function _getDataWithPosition(
        mapping(uint8 => bytes32) storage state,
        mapping(uint8 => bytes32) storage position,
        int256 curIndexPrice,
        int256 curVolatility
    ) internal view returns (Data memory data)
    {
        data = _getData(state, curIndexPrice, curVolatility);
        data.tdPowerVolume = position.getInt(P_POWERVOLUME);
        data.tdRealFuturesVolume = position.getInt(P_REALFUTURESVOLUME);
        data.tdCost = position.getInt(P_COST);
        data.tdCumulaitveFundingPerPowerVolume = position.getInt(P_CUMULAITVEFUNDINGPERPOWERVOLUME);
        data.tdCumulativeFundingPerRealFuturesVolume = position.getInt(P_CUMULATIVEFUNDINGPERREALFUTURESVOLUME);
    }

    function _saveData(
        mapping(uint8 => bytes32) storage state,
        Data memory data,
        bool changePosition
    ) internal
    {
        state.set(S_LASTTIMESTAMP, data.curTimestamp);
        state.set(S_LASTINDEXPRICE, data.curIndexPrice);
        state.set(S_LASTVOLATILITY, data.curVolatility);
        state.set(S_CUMULAITVEFUNDINGPERPOWERVOLUME, data.cumulaitveFundingPerPowerVolume);
        state.set(S_CUMULATIVEFUNDINGPERREALFUTURESVOLUME, data.cumulativeFundingPerRealFuturesVolume);
        state.set(S_TRADERSPNL, data.tradersPnl);
        state.set(S_INITIALMARGINREQUIRED, data.initialMarginRequired);

        if (changePosition) {
            state.set(S_NETPOWERVOLUME, data.netPowerVolume);
            state.set(S_NETREALFUTURESVOLUME, data.netRealFuturesVolume);
            state.set(S_NETCOST, data.netCost);
        }
    }

    function _getFunding(Data memory data, int256 liquidity) internal pure {
        data.oneHT = ONE - (r + data.curVolatility ** 2 / ONE) * data.fundingPeriod / 31536000; // 1 - hT
        data.powerTheoreticalPrice = data.curIndexPrice ** 2 / data.oneHT;
        data.powerK = DpmmPower.calculateK(data.powerAlpha, data.powerTheoreticalPrice, liquidity);
        data.futuresK = DpmmFutures.calculateK(data.futuresAlpha, data.curIndexPrice, liquidity);

        // funding
        int256 diffA;
        int256 diffB;
        {
            // i1 + i2
            int256 v1 = data.preIndexPrice + data.curIndexPrice;
            // (i1^2 + i2^2) / (1 - hT)
            int256 v2 = (data.preIndexPrice ** 2 + data.curIndexPrice ** 2) / data.oneHT;
            // (i1 + i2) * (i1^2 + i2^2) / (1 - hT)^2
            int256 v3 = v1 * v2 / data.oneHT;
            // (i1^2 + i1i2 + i2^2) / (1 - hT)
            int256 v4 = v2 + data.preIndexPrice * data.curIndexPrice / data.oneHT;

            int256 mm = data.netRealFuturesVolume + r * ONE * data.fundingPeriod / 31536000 / data.futuresK;

            diffA = v3 * data.netPowerVolume / ONE * data.futuresK / ONE +
                    v4 * (2 * mm * data.futuresK / ONE + data.netPowerVolume * data.powerK / ONE + ONE - data.oneHT) / ONE / 3;
            diffB = (v4 * data.netPowerVolume / ONE * 2 / 3 + v1 * mm / ONE / 2) * data.futuresK / ONE;

            int256 dt = (data.curTimestamp - data.preTimestamp).utoi();

            diffA = diffA * dt / data.fundingPeriod;
            diffB = diffB * dt / data.fundingPeriod;
        }

        // Slippage incured with price change in DPMM2 (Delta) incorprated into funding accounting,
        // to be compatible with OracleManager interface
        // This slippage cost will be distributed according to one's power volume,
        // whose contribution is irrelevant to its entry price
        data.preNetEffectiveFuturesVolume = 2 * data.netPowerVolume * data.preIndexPrice / data.oneHT + data.netRealFuturesVolume;
        data.curNetEffectiveFuturesVolume = 2 * data.netPowerVolume * data.curIndexPrice / data.oneHT + data.netRealFuturesVolume;
        if (data.netPowerVolume != 0) {
            int256 slippageCost = _calculateSlippageCost(
                data.curIndexPrice,
                data.futuresK,
                data.preNetEffectiveFuturesVolume,
                data.curNetEffectiveFuturesVolume - data.preNetEffectiveFuturesVolume
            );
            diffA += slippageCost * ONE / data.netPowerVolume;
        }

        unchecked { data.cumulaitveFundingPerPowerVolume += diffA; }
        unchecked { data.cumulativeFundingPerRealFuturesVolume += diffB; }
        data.funding = (data.netPowerVolume * diffA + data.netRealFuturesVolume * diffB ) / ONE;
    }

    function _calculateSlippageCost(
        int256 indexPrice,
        int256 futuresK,
        int256 netFuturesVolume,
        int256 tradeFuturesVolume
    ) internal pure returns (int256) {
        return (2 * netFuturesVolume + tradeFuturesVolume) * indexPrice / ONE * futuresK / ONE / 2 * tradeFuturesVolume / ONE;
    }

    function _getTradersPnl(Data memory data) internal pure {
        int256 netPowerValue = -DpmmPower.calculateCost(
            data.powerTheoreticalPrice, data.powerK, data.netPowerVolume, -data.netPowerVolume
        );
        int256 netRealFuturesValue = data.netRealFuturesVolume * data.curIndexPrice / ONE;
        int256 slippageCost = _calculateSlippageCost(
            data.curIndexPrice, data.futuresK, data.curNetEffectiveFuturesVolume, -data.curNetEffectiveFuturesVolume
        );
        data.tradersPnl = netPowerValue + netRealFuturesValue - data.netCost - slippageCost;
    }

    // Initial margin per volume = 2 * |curIndexPrice - averageEntryPrice| * curIndexPrice * initialMarginRatio
    //                           + (curIndexPrice * initialMarginRatio)^2
    function _calculateInitialMarginRequired(
        int256 indexPrice,
        int256 oneHT,
        int256 powerVolume,
        int256 realFuturesVolume,
        int256 initialMarginRatio
    ) internal pure returns (int256)
    {
        if (powerVolume == 0) {
            return 0;
        } else {
            int256 averageEntryPrice = -realFuturesVolume * oneHT / powerVolume / 2;
            int256 dx = indexPrice * initialMarginRatio / ONE;
            return ((indexPrice - averageEntryPrice).abs() * 2 + dx) * dx / ONE * powerVolume.abs() / ONE;
        }
    }

    function _getInitialMarginRequired(Data memory data) internal pure {
        data.initialMarginRequired = _calculateInitialMarginRequired(
            data.curIndexPrice,
            data.oneHT,
            data.netPowerVolume,
            data.netRealFuturesVolume,
            data.initialMarginRatio
        );
    }

    function _calculateTraderPnl(Data memory data) internal pure returns (int256) {
        int256 powerValue = data.tdPowerVolume * data.powerTheoreticalPrice / ONE;
        int256 realFuturesValue = data.tdRealFuturesVolume * data.curIndexPrice / ONE;
        return powerValue + realFuturesValue - data.tdCost;
    }

    function _getRemoveLiquidityPenalty(
        Data memory data,
        int256 liquidity,
        int256 removedLiquidity
    ) internal pure {
        (int256 oldPowerK, int256 oldFuturesK, int256 oldTradersPnl) = (data.powerK, data.futuresK, data.tradersPnl);
        data.powerK = DpmmPower.calculateK(data.powerAlpha, data.powerTheoreticalPrice, liquidity - removedLiquidity);
        data.futuresK = DpmmFutures.calculateK(data.futuresAlpha, data.curIndexPrice, liquidity - removedLiquidity);
        _getTradersPnl(data);
        int256 newTradersPnl = data.tradersPnl;
        (data.powerK, data.futuresK) = (oldPowerK, oldFuturesK);
        if (newTradersPnl > oldTradersPnl) {
            data.removeLiquidityPenalty = newTradersPnl - oldTradersPnl;
        } else {
            data.tradersPnl = oldTradersPnl;
        }
    }

}
