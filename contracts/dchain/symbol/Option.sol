// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './IOption.sol';
import '../../library/SafeMath.sol';
import '../../library/Bytes32Map.sol';
import '../../library/EverlastingOptionPricing.sol';
import '../../library/DpmmOption.sol';

library Option {

    using Bytes32Map for mapping(uint8 => bytes32);
    using SafeMath for uint256;
    using SafeMath for int256;

    error WrongParameterLength();
    error InvalidTradeVolume();
    error CloseOnly();
    error SlippageExceedsLimit();
    error MarkExceedsLimit();
    error OpenInterestExceedsLimit();
    error StartingPriceShiftExceedsLimit();
    error NoVolumeToForceClose();

    event UpdateOptionParameter(bytes32 symbolId);
    event RemoveOption(bytes32 symbolId);
    event SettleOptionOnAddLiquidity(
        bytes32 indexed symbolId,
        IOption.EventDataOnAddLiquidity data
    );
    event SettleOptionOnRemoveLiquidity(
        bytes32 indexed symbolId,
        IOption.EventDataOnRemoveLiquidity data
    );
    event SettleOptionOnTraderWithPosition(
        bytes32 indexed symbolId,
        uint256 indexed pTokenId,
        IOption.EventDataOnTraderWithPosition data
    );
    event SettleOptionOnTrade(
        bytes32 indexed symbolId,
        uint256 indexed pTokenId,
        IOption.EventDataOnTrade data
    );
    event SettleOptionOnLiquidate(
        bytes32 indexed symbolId,
        uint256 indexed pTokenId,
        IOption.EventDataOnLiquidate data
    );
    event SettleOptionOnForceClose(
        bytes32 indexed symbolId,
        uint256 indexed pTokenId,
        IOption.EventDataOnForceClose data
    );

    // parameters
    uint8 constant S_PRICEID                    = 1;
    uint8 constant S_VOLATILITYID               = 2;
    uint8 constant S_STRIKEPRICE                = 3;
    uint8 constant S_FUNDINGPERIOD              = 4;
    uint8 constant S_MINTRADEVOLUME             = 5;
    uint8 constant S_ALPHA                      = 6;
    uint8 constant S_FEERATIONOTIONAL           = 7;
    uint8 constant S_FEERATIOMARK               = 8;
    uint8 constant S_INITIALMARGINRATIO         = 9;
    uint8 constant S_MAINTENANCEMARGINRATIO     = 10;
    uint8 constant S_MININITIALMARGINRATIO      = 11;
    uint8 constant S_STARTINGPRICESHIFTLIMIT    = 12;
    uint8 constant S_ISCALL                     = 13;
    uint8 constant S_ISCLOSEONLY                = 14;
    // states
    uint8 constant S_LASTTIMESTAMP              = 101;
    uint8 constant S_LASTINDEXPRICE             = 102;
    uint8 constant S_LASTVOLATILITY             = 103;
    uint8 constant S_NETVOLUME                  = 104;
    uint8 constant S_NETCOST                    = 105;
    uint8 constant S_OPENVOLUME                 = 106;
    uint8 constant S_TRADERSPNL                 = 107;
    uint8 constant S_INITIALMARGINREQUIRED      = 108;
    uint8 constant S_CUMULATIVEFUNDINGPERVOLUME = 109;
    uint8 constant S_LASTNETVOLUME              = 110;
    uint8 constant S_LASTNETVOLUMEBLOCK         = 111;

    uint8 constant P_VOLUME                     = 1;
    uint8 constant P_COST                       = 2;
    uint8 constant P_CUMULATIVEFUNDINGPERVOLUME = 3;

    uint8 constant ACTION_ADDLIQUIDITY      = 1;
    uint8 constant ACTION_REMOVELIQUIDITY   = 2;
    uint8 constant ACTION_TRADERWITHPOSTION = 3;
    uint8 constant ACTION_TRADE             = 4;
    uint8 constant ACTION_LIQUIDATE         = 5;

    int256 constant ONE = 1e18;

    //================================================================================
    // Getters
    //================================================================================

    function getState(mapping(uint8 => bytes32) storage state)
    external view returns (bytes32[] memory s)
    {
        s = new bytes32[](25);

        s[0]  = state.getBytes32(S_PRICEID);
        s[1]  = state.getBytes32(S_VOLATILITYID);
        s[2]  = state.getBytes32(S_STRIKEPRICE);
        s[3]  = state.getBytes32(S_FUNDINGPERIOD);
        s[4]  = state.getBytes32(S_MINTRADEVOLUME);
        s[5]  = state.getBytes32(S_ALPHA);
        s[6]  = state.getBytes32(S_FEERATIONOTIONAL);
        s[7]  = state.getBytes32(S_FEERATIOMARK);
        s[8]  = state.getBytes32(S_INITIALMARGINRATIO);
        s[9]  = state.getBytes32(S_MAINTENANCEMARGINRATIO);
        s[10] = state.getBytes32(S_MININITIALMARGINRATIO);
        s[11] = state.getBytes32(S_STARTINGPRICESHIFTLIMIT);
        s[12] = state.getBytes32(S_ISCALL);
        s[13] = state.getBytes32(S_ISCLOSEONLY);

        s[14] = state.getBytes32(S_LASTTIMESTAMP);
        s[15] = state.getBytes32(S_LASTINDEXPRICE);
        s[16] = state.getBytes32(S_LASTVOLATILITY);
        s[17] = state.getBytes32(S_NETVOLUME);
        s[18] = state.getBytes32(S_NETCOST);
        s[19] = state.getBytes32(S_OPENVOLUME);
        s[20] = state.getBytes32(S_TRADERSPNL);
        s[21] = state.getBytes32(S_INITIALMARGINREQUIRED);
        s[22] = state.getBytes32(S_CUMULATIVEFUNDINGPERVOLUME);
        s[23] = state.getBytes32(S_LASTNETVOLUME);
        s[24] = state.getBytes32(S_LASTNETVOLUMEBLOCK);
    }

    function getPosition(mapping(uint8 => bytes32) storage position)
    external view returns (bytes32[] memory pos)
    {
        pos = new bytes32[](3);
        pos[0] = position.getBytes32(P_VOLUME);
        pos[1] = position.getBytes32(P_COST);
        pos[2] = position.getBytes32(P_CUMULATIVEFUNDINGPERVOLUME);
    }

    //================================================================================
    // Setters
    //================================================================================

    function setParameter(
        bytes32 symbolId,
        mapping(uint8 => bytes32) storage state,
        bytes32[] memory p
    ) external {
        if (p.length != 14) {
            revert WrongParameterLength();
        }
        state.set(S_PRICEID, p[0]);
        state.set(S_VOLATILITYID, p[1]);
        state.set(S_STRIKEPRICE, p[2]);
        state.set(S_FUNDINGPERIOD, p[3]);
        state.set(S_MINTRADEVOLUME, p[4]);
        state.set(S_ALPHA, p[5]);
        state.set(S_FEERATIONOTIONAL, p[6]);
        state.set(S_FEERATIOMARK, p[7]);
        state.set(S_INITIALMARGINRATIO, p[8]);
        state.set(S_MAINTENANCEMARGINRATIO, p[9]);
        state.set(S_MININITIALMARGINRATIO, p[10]);
        state.set(S_STARTINGPRICESHIFTLIMIT, p[11]);
        state.set(S_ISCALL, p[12]);
        state.set(S_ISCLOSEONLY, p[13]);
        emit UpdateOptionParameter(symbolId);
    }

    function setParameterOfId(
        bytes32 symbolId,
        mapping(uint8 => bytes32) storage state,
        uint8 parameterId,
        bytes32 value
    ) external {
        state.set(parameterId, value);
        emit UpdateOptionParameter(symbolId);
    }

    function removeSymbol(bytes32 symbolId, mapping(uint8 => bytes32) storage state) external {
        require(state.getInt(S_OPENVOLUME) == 0, 'Have position');
        state.set(S_PRICEID, bytes32(0));
        state.set(S_VOLATILITYID, bytes32(0));
        state.set(S_STRIKEPRICE, bytes32(0));
        state.set(S_FUNDINGPERIOD, bytes32(0));
        state.set(S_MINTRADEVOLUME, bytes32(0));
        state.set(S_ALPHA, bytes32(0));
        state.set(S_FEERATIONOTIONAL, bytes32(0));
        state.set(S_FEERATIOMARK, bytes32(0));
        state.set(S_INITIALMARGINRATIO, bytes32(0));
        state.set(S_MAINTENANCEMARGINRATIO, bytes32(0));
        state.set(S_MININITIALMARGINRATIO, bytes32(0));
        state.set(S_STARTINGPRICESHIFTLIMIT, bytes32(0));
        state.set(S_ISCALL, bytes32(0));
        state.set(S_ISCLOSEONLY, true);
        emit RemoveOption(symbolId);
    }

    //================================================================================
    // Settlers
    //================================================================================

    function settleOnAddLiquidity(
        mapping(uint8 => bytes32) storage state,
        IOption.VarOnAddLiquidity memory v
    ) external returns (IOption.SettlementOnAddLiquidity memory s)
    {
        (Data memory data, bool skip) = _getData(ACTION_ADDLIQUIDITY, state);
        if (skip) return s;

        _getFunding(data, v.indexPrice, v.volatility, v.liquidity);
        _getTradersPnl(data);
        _getInitialMarginRequired(data, v.indexPrice);

        s.settled = true;
        s.funding = data.funding;
        s.diffTradersPnl = data.tradersPnl - state.getInt(S_TRADERSPNL);
        s.diffInitialMarginRequired = data.initialMarginRequired - state.getInt(S_INITIALMARGINREQUIRED);

        state.set(S_LASTTIMESTAMP, data.curTimestamp);
        state.set(S_LASTINDEXPRICE, v.indexPrice);
        state.set(S_LASTVOLATILITY, v.volatility);
        state.set(S_TRADERSPNL, data.tradersPnl);
        state.set(S_INITIALMARGINREQUIRED, data.initialMarginRequired);
        state.set(S_CUMULATIVEFUNDINGPERVOLUME, data.cumulativeFundingPerVolume);

        emit SettleOptionOnAddLiquidity(v.symbolId, IOption.EventDataOnAddLiquidity({
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
        IOption.VarOnRemoveLiquidity memory v
    ) external returns (IOption.SettlementOnRemoveLiquidity memory s)
    {
        (Data memory data, bool skip) = _getData(ACTION_REMOVELIQUIDITY, state);
        if (skip) return s;

        _getFunding(data, v.indexPrice, v.volatility, v.liquidity);
        _getTradersPnl(data);
        _getInitialMarginRequired(data, v.indexPrice);
        _getRemoveLiquidityPenalty(data, v.indexPrice, v.liquidity, v.removedLiquidity);

        s.settled = true;
        s.funding = data.funding;
        s.diffTradersPnl = data.tradersPnl - state.getInt(S_TRADERSPNL);
        s.diffInitialMarginRequired = data.initialMarginRequired - state.getInt(S_INITIALMARGINREQUIRED);
        s.removeLiquidityPenalty = data.removeLiquidityPenalty;

        state.set(S_LASTTIMESTAMP, data.curTimestamp);
        state.set(S_LASTINDEXPRICE, v.indexPrice);
        state.set(S_LASTVOLATILITY, v.volatility);
        state.set(S_TRADERSPNL, data.tradersPnl);
        state.set(S_INITIALMARGINREQUIRED, data.initialMarginRequired);
        state.set(S_CUMULATIVEFUNDINGPERVOLUME, data.cumulativeFundingPerVolume);

        emit SettleOptionOnRemoveLiquidity(v.symbolId, IOption.EventDataOnRemoveLiquidity({
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
        IOption.VarOnTraderWithPosition memory v
    ) external returns (IOption.SettlementOnTraderWithPosition memory s)
    {
        Data memory data = _getDataWithPosition(ACTION_TRADERWITHPOSTION, state, position);

        _getFunding(data, v.indexPrice, v.volatility, v.liquidity);
        _getTradersPnl(data);
        _getInitialMarginRequired(data, v.indexPrice);

        s.funding = data.funding;
        s.diffTradersPnl = data.tradersPnl - state.getInt(S_TRADERSPNL);
        s.diffInitialMarginRequired = data.initialMarginRequired - state.getInt(S_INITIALMARGINREQUIRED);

        {
            int256 diff = data.cumulativeFundingPerVolume.minusUnchecked(data.tdCumulativeFundingPerVolume);
            s.traderFunding = data.tdVolume * diff / ONE;
        }

        s.traderPnl = data.tdVolume * data.theoreticalPrice / ONE - data.tdCost;
        s.traderInitialMarginRequired = data.tdVolume.abs() * data.initialMarginPerVolume / ONE;

        state.set(S_LASTTIMESTAMP, data.curTimestamp);
        state.set(S_LASTINDEXPRICE, v.indexPrice);
        state.set(S_LASTVOLATILITY, v.volatility);
        state.set(S_TRADERSPNL, data.tradersPnl);
        state.set(S_INITIALMARGINREQUIRED, data.initialMarginRequired);
        state.set(S_CUMULATIVEFUNDINGPERVOLUME, data.cumulativeFundingPerVolume);

        position.set(P_CUMULATIVEFUNDINGPERVOLUME, data.cumulativeFundingPerVolume);

        emit SettleOptionOnTraderWithPosition(v.symbolId, v.pTokenId, IOption.EventDataOnTraderWithPosition({
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

    function settleOnTrade(
        mapping(uint8 => bytes32) storage state,
        mapping(uint8 => bytes32) storage position,
        IOption.VarOnTrade memory v
    ) external returns (IOption.SettlementOnTrade memory s)
    {
        _updateLastNetVolume(state);

        Data memory data = _getDataWithPosition(ACTION_TRADE, state, position);

        if (v.tradeVolume == 0 || v.tradeVolume % state.getInt(S_MINTRADEVOLUME) != 0) {
            revert InvalidTradeVolume();
        }

        if (state.getBool(S_ISCLOSEONLY)) {
            if (
                !(data.tdVolume > 0 && v.tradeVolume < 0 && data.tdVolume + v.tradeVolume >= 0) &&
                !(data.tdVolume < 0 && v.tradeVolume > 0 && data.tdVolume + v.tradeVolume <= 0)
            ) {
                revert CloseOnly();
            }
        }

        _getFunding(data, v.indexPrice, v.volatility, v.liquidity);

        {
            int256 diff = data.cumulativeFundingPerVolume.minusUnchecked(data.tdCumulativeFundingPerVolume);
            s.traderFunding = data.tdVolume * diff / ONE;
        }

        s.tradeCost = DpmmOption.calculateCost(
            data.theoreticalPrice, data.k, data.netVolume, v.tradeVolume
        );
        s.tradeFee = SafeMath.min(
            v.indexPrice * v.tradeVolume.abs() / ONE * state.getInt(S_FEERATIONOTIONAL) / ONE,
            s.tradeCost.abs() * state.getInt(S_FEERATIOMARK) / ONE
        );

        {
            // check slippage
            int256 averagePrice = s.tradeCost * ONE / v.tradeVolume;
            if (
                !(v.tradeVolume > 0 && averagePrice <= v.priceLimit) &&
                !(v.tradeVolume < 0 && averagePrice >= v.priceLimit)
            ) {
                revert SlippageExceedsLimit();
            }
        }

        if ((data.tdVolume > 0 || v.tradeVolume > 0) && (data.tdVolume < 0 || v.tradeVolume < 0)) {
            if (data.tdVolume.abs() <= v.tradeVolume.abs()) {
                s.tradeRealizedCost = s.tradeCost * data.tdVolume.abs() / v.tradeVolume.abs() + data.tdCost;
            } else {
                s.tradeRealizedCost = data.tdCost * v.tradeVolume.abs() / data.tdVolume.abs() + s.tradeCost;
            }
        }

        data.netVolume += v.tradeVolume;
        data.netCost += s.tradeCost - s.tradeRealizedCost;
        _getTradersPnl(data);
        _getInitialMarginRequired(data, v.indexPrice);

        if (DpmmOption.calculateMarkPrice(data.theoreticalPrice, data.k, data.netVolume) <= 0) {
            revert MarkExceedsLimit();
        }

        {
            int256 diffOpenVolume = (data.tdVolume + v.tradeVolume).abs() - data.tdVolume.abs();
            data.openVolume += diffOpenVolume;
            if (diffOpenVolume > 0) {
                int256 openInterestRatio = v.indexPrice * data.openVolume / v.liquidity;
                if (
                    state.getInt(S_MININITIALMARGINRATIO) * ONE < data.delta.abs() * data.alpha / ONE * openInterestRatio &&
                    data.initialMarginRatio * ONE < data.alpha * openInterestRatio
                ) {
                    revert OpenInterestExceedsLimit();
                }
            }
        }

        {
            int256 volume1 = data.tdVolume;
            int256 volume2 = data.tdVolume + v.tradeVolume;

            if (volume1 == 0 || volume2 == 0) { // full operation, set bit 1
                s.positionChange += 2;
            }

            if (!((volume2 >= 0 && volume1 > volume2) || (volume2 <= 0 && volume1 < volume2))) { // increase volume, set bit 0
                s.positionChange += 1;
            }

            if (data.netVolume.abs() > (data.netVolume - v.tradeVolume).abs()) {
                s.positionChange += 4; // increase net volume, set bit 2
            }
        }

        data.tdVolume += v.tradeVolume;
        data.tdCost += s.tradeCost - s.tradeRealizedCost;
        data.tdCumulativeFundingPerVolume = data.cumulativeFundingPerVolume;

        s.funding = data.funding;
        s.diffTradersPnl = data.tradersPnl - state.getInt(S_TRADERSPNL);
        s.diffInitialMarginRequired = data.initialMarginRequired - state.getInt(S_INITIALMARGINREQUIRED);

        {
            int256 traderInitialMarginPerVolume = SafeMath.max(
                v.indexPrice * state.getInt(S_MININITIALMARGINRATIO) / ONE,
                data.initialMarginPerVolume
            );
            s.traderPnl = data.tdVolume * data.theoreticalPrice / ONE - data.tdCost;
            s.traderInitialMarginRequired = data.tdVolume.abs() * traderInitialMarginPerVolume / ONE;
        }

        state.set(S_LASTTIMESTAMP, data.curTimestamp);
        state.set(S_LASTINDEXPRICE, v.indexPrice);
        state.set(S_LASTVOLATILITY, v.volatility);
        state.set(S_NETVOLUME, data.netVolume);
        state.set(S_NETCOST, data.netCost);
        state.set(S_OPENVOLUME, data.openVolume);
        state.set(S_TRADERSPNL, data.tradersPnl);
        state.set(S_INITIALMARGINREQUIRED, data.initialMarginRequired);
        state.set(S_CUMULATIVEFUNDINGPERVOLUME, data.cumulativeFundingPerVolume);

        position.set(P_VOLUME, data.tdVolume);
        position.set(P_COST, data.tdCost);
        position.set(P_CUMULATIVEFUNDINGPERVOLUME, data.tdCumulativeFundingPerVolume);

        emit SettleOptionOnTrade(v.symbolId, v.pTokenId, IOption.EventDataOnTrade({
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
        IOption.VarOnForceClose memory v
    ) external returns (IOption.SettlementOnForceClose memory s)
    {
        Data memory data = _getDataWithPosition(ACTION_TRADE, state, position);

        if (data.tdVolume == 0) {
            revert NoVolumeToForceClose();
        }

        _getFunding(data, v.indexPrice, v.volatility, v.liquidity);

        {
            int256 diff = data.cumulativeFundingPerVolume.minusUnchecked(data.tdCumulativeFundingPerVolume);
            s.traderFunding = data.tdVolume * diff / ONE;
        }

        int256 tradeVolume = -data.tdVolume;
        s.tradeCost = DpmmOption.calculateCost(
            data.theoreticalPrice, data.k, data.netVolume, tradeVolume
        );
        s.tradeRealizedCost = data.tdCost + s.tradeCost;

        data.netVolume -= data.tdVolume;
        data.netCost -= data.tdCost;
        _getTradersPnl(data);
        _getInitialMarginRequired(data, v.indexPrice);

        data.openVolume -= data.tdVolume.abs();

        data.tdVolume = 0;
        data.tdCost = 0;
        data.tdCumulativeFundingPerVolume = data.cumulativeFundingPerVolume;

        s.funding = data.funding;
        s.diffTradersPnl = data.tradersPnl - state.getInt(S_TRADERSPNL);
        s.diffInitialMarginRequired = data.initialMarginRequired - state.getInt(S_INITIALMARGINREQUIRED);

        state.set(S_LASTTIMESTAMP, data.curTimestamp);
        state.set(S_LASTINDEXPRICE, v.indexPrice);
        state.set(S_LASTVOLATILITY, v.volatility);
        state.set(S_NETVOLUME, data.netVolume);
        state.set(S_NETCOST, data.netCost);
        state.set(S_OPENVOLUME, data.openVolume);
        state.set(S_TRADERSPNL, data.tradersPnl);
        state.set(S_INITIALMARGINREQUIRED, data.initialMarginRequired);
        state.set(S_CUMULATIVEFUNDINGPERVOLUME, data.cumulativeFundingPerVolume);

        position.set(P_VOLUME, data.tdVolume);
        position.set(P_COST, data.tdCost);
        position.set(P_CUMULATIVEFUNDINGPERVOLUME, data.tdCumulativeFundingPerVolume);

        emit SettleOptionOnForceClose(v.symbolId, v.pTokenId, IOption.EventDataOnForceClose({
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
        IOption.VarOnLiquidate memory v
    ) external returns (IOption.SettlementOnLiquidate memory s)
    {
        _updateLastNetVolume(state);

        Data memory data = _getDataWithPosition(ACTION_LIQUIDATE, state, position);

        _getFunding(data, v.indexPrice, v.volatility, v.liquidity);

        {
            // check price shift
            int256 lastNetVolume = state.getInt(S_LASTNETVOLUME);
            int256 netVolumeShiftAllowance = state.getInt(S_STARTINGPRICESHIFTLIMIT) * ONE / data.k;
            if (
                !(data.tdVolume > 0 && data.netVolume + netVolumeShiftAllowance >= lastNetVolume) &&
                !(data.tdVolume < 0 && data.netVolume <= netVolumeShiftAllowance + lastNetVolume)
            ) {
                revert StartingPriceShiftExceedsLimit();
            }
        }

        {
            int256 diff = data.cumulativeFundingPerVolume.minusUnchecked(data.tdCumulativeFundingPerVolume);
            s.traderFunding = data.tdVolume * diff / ONE;
        }

        s.tradeVolume = -data.tdVolume;
        s.tradeCost = DpmmOption.calculateCost(
            data.theoreticalPrice, data.k, data.netVolume, -data.tdVolume
        );
        s.tradeRealizedCost = s.tradeCost + data.tdCost;

        data.netVolume -= data.tdVolume;
        data.netCost -= data.tdCost;
        _getTradersPnl(data);
        _getInitialMarginRequired(data, v.indexPrice);

        data.openVolume -= data.tdVolume.abs();

        s.funding = data.funding;
        s.diffTradersPnl = data.tradersPnl - state.getInt(S_TRADERSPNL);
        s.diffInitialMarginRequired = data.initialMarginRequired - state.getInt(S_INITIALMARGINREQUIRED);

        s.traderPnl = data.tdVolume * data.theoreticalPrice / ONE - data.tdCost;
        s.traderMaintenanceMarginRequired = data.tdVolume.abs() * data.maintenanceMarginPerVolume / ONE;

        state.set(S_LASTTIMESTAMP, data.curTimestamp);
        state.set(S_LASTINDEXPRICE, v.indexPrice);
        state.set(S_LASTVOLATILITY, v.volatility);
        state.set(S_NETVOLUME, data.netVolume);
        state.set(S_NETCOST, data.netCost);
        state.set(S_OPENVOLUME, data.openVolume);
        state.set(S_TRADERSPNL, data.tradersPnl);
        state.set(S_INITIALMARGINREQUIRED, data.initialMarginRequired);
        state.set(S_CUMULATIVEFUNDINGPERVOLUME, data.cumulativeFundingPerVolume);

        delete position[P_VOLUME];
        delete position[P_COST];
        delete position[P_CUMULATIVEFUNDINGPERVOLUME];

        emit SettleOptionOnLiquidate(v.symbolId, v.pTokenId, IOption.EventDataOnLiquidate({
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
        int256 preTimestamp;
        int256 curTimestamp;
        int256 netVolume;
        int256 netCost;
        int256 cumulativeFundingPerVolume;
        int256 openVolume;
        // parameters
        int256 strikePrice;
        int256 fundingPeriod;
        int256 alpha;
        int256 initialMarginRatio;
        int256 maintenanceMarginRatio;
        bool   isCall;
        // position
        int256 tdVolume;
        int256 tdCost;
        int256 tdCumulativeFundingPerVolume;
        // calculations
        int256 intrinsicValue;
        int256 theoreticalPrice;
        int256 delta;
        int256 gamma;
        int256 k;
        int256 funding;
        int256 tradersPnl;
        int256 initialMarginPerVolume;
        int256 maintenanceMarginPerVolume;
        int256 initialMarginRequired;
        int256 removeLiquidityPenalty;
    }

    function _getData(uint8 action, mapping(uint8 => bytes32) storage state)
    internal view returns (Data memory data, bool skip)
    {
        data.preTimestamp = state.getInt(S_LASTTIMESTAMP);
        data.curTimestamp = int256(block.timestamp);
        if (action == ACTION_ADDLIQUIDITY && data.preTimestamp == data.curTimestamp) {
            return (data, true);
        }
        data.netVolume = state.getInt(S_NETVOLUME);
        if ((action == ACTION_ADDLIQUIDITY || action == ACTION_REMOVELIQUIDITY) && data.netVolume == 0) {
            return (data, true);
        }
        data.netCost = state.getInt(S_NETCOST);
        data.cumulativeFundingPerVolume = state.getInt(S_CUMULATIVEFUNDINGPERVOLUME);
        if (action == ACTION_TRADE || action == ACTION_LIQUIDATE) {
            data.openVolume = state.getInt(S_OPENVOLUME);
        }

        data.strikePrice = state.getInt(S_STRIKEPRICE);
        data.fundingPeriod = state.getInt(S_FUNDINGPERIOD);
        data.alpha = state.getInt(S_ALPHA);
        data.initialMarginRatio = state.getInt(S_INITIALMARGINRATIO);
        data.maintenanceMarginRatio = state.getInt(S_MAINTENANCEMARGINRATIO);
        data.isCall = state.getBool(S_ISCALL);
    }

    function _getDataWithPosition(
        uint8 action,
        mapping(uint8 => bytes32) storage state,
        mapping(uint8 => bytes32) storage position
    ) internal view returns (Data memory data)
    {
        (data, ) = _getData(action, state);
        data.tdVolume = position.getInt(P_VOLUME);
        data.tdCost = position.getInt(P_COST);
        data.tdCumulativeFundingPerVolume = position.getInt(P_CUMULATIVEFUNDINGPERVOLUME);
    }

    function _getFunding(
        Data memory data,
        int256 indexPrice,
        int256 volatility,
        int256 liquidity
    ) internal pure {
        (
            data.theoreticalPrice,
            data.intrinsicValue,
            data.delta,
            data.gamma
        ) = EverlastingOptionPricing.calculateEverlastingOption(
            indexPrice,
            data.strikePrice,
            volatility,
            data.isCall
        );

        data.k = DpmmOption.calculateK(
            data.alpha, indexPrice, data.theoreticalPrice, data.delta, liquidity
        );
        int256 markPrice = DpmmOption.calculateMarkPrice(
            data.theoreticalPrice, data.k, data.netVolume
        );

        int256 diffFundingPerVolume = (markPrice - data.intrinsicValue) * (data.curTimestamp - data.preTimestamp) / data.fundingPeriod;
        data.funding = diffFundingPerVolume * data.netVolume / ONE;
        data.cumulativeFundingPerVolume = data.cumulativeFundingPerVolume.addUnchecked(diffFundingPerVolume);
    }

    function _getTradersPnl(Data memory data) internal pure {
        data.tradersPnl = -(DpmmOption.calculateCost(
            data.theoreticalPrice, data.k, data.netVolume, -data.netVolume
        ) + data.netCost);
    }

    function _getInitialMarginRequired(Data memory data, int256 indexPrice) internal pure {
        int256 dS = indexPrice * data.maintenanceMarginRatio / ONE;
        int256 deltaPart = data.delta.abs() * dS / ONE;
        int256 gammaPart = data.gamma.abs() * dS / ONE * dS / ONE / 2;
        data.maintenanceMarginPerVolume = deltaPart + gammaPart;
        data.initialMarginPerVolume = data.maintenanceMarginPerVolume * data.initialMarginRatio / data.maintenanceMarginRatio;
        data.initialMarginRequired = data.netVolume.abs() * data.initialMarginPerVolume / ONE;
    }

    function _getRemoveLiquidityPenalty(
        Data memory data,
        int256 indexPrice,
        int256 liquidity,
        int256 removedLiquidity
    ) internal pure {
        int256 newK = DpmmOption.calculateK(
            data.alpha, indexPrice, data.theoreticalPrice, data.delta, liquidity - removedLiquidity
        );
        int256 newTradersPnl = -(DpmmOption.calculateCost(
            data.theoreticalPrice, newK, data.netVolume, -data.netVolume
        ) + data.netCost);
        if (newTradersPnl > data.tradersPnl) {
            data.removeLiquidityPenalty = newTradersPnl - data.tradersPnl;
            data.tradersPnl = newTradersPnl;
        }
    }

    // update lastNetVolume if this is the first transaction in block
    function _updateLastNetVolume(mapping(uint8 => bytes32) storage state) internal {
        if (block.number > state.getUint(S_LASTNETVOLUMEBLOCK)) {
            state.set(S_LASTNETVOLUMEBLOCK, block.number);
            state.set(S_LASTNETVOLUME, state.getInt(S_NETVOLUME));
        }
    }

}
