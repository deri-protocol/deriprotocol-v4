// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './IPower.sol';
import '../../library/SafeMath.sol';
import '../../library/Bytes32Map.sol';
import '../../library/DpmmPower.sol';

library Power {

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

    event UpdatePowerParameter(bytes32 symbolId);
    event RemovePower(bytes32 symbolId);
    event SettlePowerOnAddLiquidity(
        bytes32 indexed symbolId,
        IPower.EventDataOnAddLiquidity data
    );
    event SettlePowerOnRemoveLiquidity(
        bytes32 indexed symbolId,
        IPower.EventDataOnRemoveLiquidity data
    );
    event SettlePowerOnTraderWithPosition(
        bytes32 indexed symbolId,
        uint256 indexed pTokenId,
        IPower.EventDataOnTraderWithPosition data
    );
    event SettlePowerOnTrade(
        bytes32 indexed symbolId,
        uint256 indexed pTokenId,
        IPower.EventDataOnTrade data
    );
    event SettlePowerOnLiquidate(
        bytes32 indexed symbolId,
        uint256 indexed pTokenId,
        IPower.EventDataOnLiquidate data
    );
    event SettlePowerOnForceClose(
        bytes32 indexed symbolId,
        uint256 indexed pTokenId,
        IPower.EventDataOnForceClose data
    );

    // parameters
    uint8 constant S_PRICEID                    = 1;
    uint8 constant S_VOLATILITYID               = 2;
    uint8 constant S_FUNDINGPERIOD              = 3;
    uint8 constant S_MINTRADEVOLUME             = 4;
    uint8 constant S_ALPHA                      = 5;
    uint8 constant S_FEERATIO                   = 6;
    uint8 constant S_INITIALMARGINRATIO         = 7;
    uint8 constant S_MAINTENANCEMARGINRATIO     = 8;
    uint8 constant S_STARTINGPRICESHIFTLIMIT    = 9;
    uint8 constant S_ISCLOSEONLY                = 10;
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
        s = new bytes32[](21);

        s[0]  = state.getBytes32(S_PRICEID);
        s[1]  = state.getBytes32(S_VOLATILITYID);
        s[2]  = state.getBytes32(S_FUNDINGPERIOD);
        s[3]  = state.getBytes32(S_MINTRADEVOLUME);
        s[4]  = state.getBytes32(S_ALPHA);
        s[5]  = state.getBytes32(S_FEERATIO);
        s[6]  = state.getBytes32(S_INITIALMARGINRATIO);
        s[7]  = state.getBytes32(S_MAINTENANCEMARGINRATIO);
        s[8]  = state.getBytes32(S_STARTINGPRICESHIFTLIMIT);
        s[9]  = state.getBytes32(S_ISCLOSEONLY);

        s[10] = state.getBytes32(S_LASTTIMESTAMP);
        s[11] = state.getBytes32(S_LASTINDEXPRICE);
        s[12] = state.getBytes32(S_LASTVOLATILITY);
        s[13] = state.getBytes32(S_NETVOLUME);
        s[14] = state.getBytes32(S_NETCOST);
        s[15] = state.getBytes32(S_OPENVOLUME);
        s[16] = state.getBytes32(S_TRADERSPNL);
        s[17] = state.getBytes32(S_INITIALMARGINREQUIRED);
        s[18] = state.getBytes32(S_CUMULATIVEFUNDINGPERVOLUME);
        s[19] = state.getBytes32(S_LASTNETVOLUME);
        s[20] = state.getBytes32(S_LASTNETVOLUMEBLOCK);
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
        if (p.length != 10) {
            revert WrongParameterLength();
        }
        state.set(S_PRICEID, p[0]);
        state.set(S_VOLATILITYID, p[1]);
        state.set(S_FUNDINGPERIOD, p[2]);
        state.set(S_MINTRADEVOLUME, p[3]);
        state.set(S_ALPHA, p[4]);
        state.set(S_FEERATIO, p[5]);
        state.set(S_INITIALMARGINRATIO, p[6]);
        state.set(S_MAINTENANCEMARGINRATIO, p[7]);
        state.set(S_STARTINGPRICESHIFTLIMIT, p[8]);
        state.set(S_ISCLOSEONLY, p[9]);
        emit UpdatePowerParameter(symbolId);
    }

    function setParameterOfId(
        bytes32 symbolId,
        mapping(uint8 => bytes32) storage state,
        uint8 parameterId,
        bytes32 value
    ) external {
        state.set(parameterId, value);
        emit UpdatePowerParameter(symbolId);
    }

    function removeSymbol(bytes32 symbolId, mapping(uint8 => bytes32) storage state) external {
        require(state.getInt(S_OPENVOLUME) == 0, 'Have position');
        state.set(S_PRICEID, bytes32(0));
        state.set(S_VOLATILITYID, bytes32(0));
        state.set(S_FUNDINGPERIOD, bytes32(0));
        state.set(S_MINTRADEVOLUME, bytes32(0));
        state.set(S_ALPHA, bytes32(0));
        state.set(S_FEERATIO, bytes32(0));
        state.set(S_INITIALMARGINRATIO, bytes32(0));
        state.set(S_MAINTENANCEMARGINRATIO, bytes32(0));
        state.set(S_STARTINGPRICESHIFTLIMIT, bytes32(0));
        state.set(S_ISCLOSEONLY, true);
        emit RemovePower(symbolId);
    }

    //================================================================================
    // Settlers
    //================================================================================

    function settleOnAddLiquidity(
        mapping(uint8 => bytes32) storage state,
        IPower.VarOnAddLiquidity memory v
    ) external returns (IPower.SettlementOnAddLiquidity memory s)
    {
        (Data memory data, bool skip) = _getData(ACTION_ADDLIQUIDITY, state);
        if (skip) return s;

        _getFunding(data, v.indexPrice, v.volatility, v.liquidity);
        _getTradersPnl(data);
        _getInitialMarginRequired(data);

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

        emit SettlePowerOnAddLiquidity(v.symbolId, IPower.EventDataOnAddLiquidity({
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
        IPower.VarOnRemoveLiquidity memory v
    ) external returns (IPower.SettlementOnRemoveLiquidity memory s)
    {
        (Data memory data, bool skip) = _getData(ACTION_REMOVELIQUIDITY, state);
        if (skip) return s;

        _getFunding(data, v.indexPrice, v.volatility, v.liquidity);
        _getTradersPnl(data);
        _getInitialMarginRequired(data);
        _getRemoveLiquidityPenalty(data, v.liquidity, v.removedLiquidity);

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

        emit SettlePowerOnRemoveLiquidity(v.symbolId, IPower.EventDataOnRemoveLiquidity({
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
        IPower.VarOnTraderWithPosition memory v
    ) external returns (IPower.SettlementOnTraderWithPosition memory s)
    {
        Data memory data = _getDataWithPosition(ACTION_TRADERWITHPOSTION, state, position);

        _getFunding(data, v.indexPrice, v.volatility, v.liquidity);
        _getTradersPnl(data);
        _getInitialMarginRequired(data);

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

        emit SettlePowerOnTraderWithPosition(v.symbolId, v.pTokenId, IPower.EventDataOnTraderWithPosition({
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
        IPower.VarOnTrade memory v
    ) external returns (IPower.SettlementOnTrade memory s)
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

        s.tradeCost = DpmmPower.calculateCost(
            data.theoreticalPrice, data.k, data.netVolume, v.tradeVolume
        );
        s.tradeFee = s.tradeCost.abs() * state.getInt(S_FEERATIO) / ONE;

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
        _getInitialMarginRequired(data);

        if (DpmmPower.calculateMarkPrice(data.theoreticalPrice, data.k, data.netVolume) <= 0) {
            revert MarkExceedsLimit();
        }

        {
            int256 diffOpenVolume = (data.tdVolume + v.tradeVolume).abs() - data.tdVolume.abs();
            data.openVolume += diffOpenVolume;
            if (diffOpenVolume > 0) {
                int256 openInterestRatio = data.theoreticalPrice * data.openVolume / v.liquidity;
                if (data.initialMarginRatio * ONE < 2 * data.alpha * openInterestRatio) {
                    revert OpenInterestExceedsLimit();
                }
            }
        }

        if (data.tdVolume == 0) {
            s.positionChange = 1;
        } else if (data.tdVolume + v.tradeVolume == 0) {
            s.positionChange = -1;
        }

        data.tdVolume += v.tradeVolume;
        data.tdCost += s.tradeCost - s.tradeRealizedCost;
        data.tdCumulativeFundingPerVolume = data.cumulativeFundingPerVolume;

        s.funding = data.funding;
        s.diffTradersPnl = data.tradersPnl - state.getInt(S_TRADERSPNL);
        s.diffInitialMarginRequired = data.initialMarginRequired - state.getInt(S_INITIALMARGINREQUIRED);

        s.traderPnl = data.tdVolume * data.theoreticalPrice / ONE - data.tdCost;
        s.traderInitialMarginRequired = data.tdVolume.abs() * data.initialMarginPerVolume / ONE;

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

        emit SettlePowerOnTrade(v.symbolId, v.pTokenId, IPower.EventDataOnTrade({
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
        IPower.VarOnForceClose memory v
    ) external returns (IPower.SettlementOnForceClose memory s)
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
        s.tradeCost = DpmmPower.calculateCost(
            data.theoreticalPrice, data.k, data.netVolume, tradeVolume
        );
        s.tradeRealizedCost = data.tdCost + s.tradeCost;

        data.netVolume -= data.tdVolume;
        data.netCost -= data.tdCost;
        _getTradersPnl(data);
        _getInitialMarginRequired(data);

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

        emit SettlePowerOnForceClose(v.symbolId, v.pTokenId, IPower.EventDataOnForceClose({
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
        IPower.VarOnLiquidate memory v
    ) external returns (IPower.SettlementOnLiquidate memory s)
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
        s.tradeCost = DpmmPower.calculateCost(
            data.theoreticalPrice, data.k, data.netVolume, -data.tdVolume
        );
        s.tradeRealizedCost = s.tradeCost + data.tdCost;

        data.netVolume -= data.tdVolume;
        data.netCost -= data.tdCost;
        _getTradersPnl(data);
        _getInitialMarginRequired(data);

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

        emit SettlePowerOnLiquidate(v.symbolId, v.pTokenId, IPower.EventDataOnLiquidate({
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
        int256 fundingPeriod;
        int256 alpha;
        int256 initialMarginRatio;
        int256 maintenanceMarginRatio;
        // position
        int256 tdVolume;
        int256 tdCost;
        int256 tdCumulativeFundingPerVolume;
        // calculations
        int256 powerPrice;
        int256 theoreticalPrice;
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

        data.fundingPeriod = state.getInt(S_FUNDINGPERIOD);
        data.alpha = state.getInt(S_ALPHA);
        data.initialMarginRatio = state.getInt(S_INITIALMARGINRATIO);
        data.maintenanceMarginRatio = state.getInt(S_MAINTENANCEMARGINRATIO);
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
        int256 oneHT = ONE - volatility ** 2 / ONE * data.fundingPeriod / 31536000; // 1 - hT
        data.powerPrice = indexPrice ** 2 / ONE;
        data.theoreticalPrice = data.powerPrice * ONE / oneHT;

        data.k = DpmmPower.calculateK(data.alpha, data.theoreticalPrice, liquidity);
        int256 markPrice = DpmmPower.calculateMarkPrice(
            data.theoreticalPrice, data.k, data.netVolume
        );
        int256 diffFundingPerVolume = (markPrice - data.powerPrice) * (data.curTimestamp - data.preTimestamp) / data.fundingPeriod;
        data.funding = diffFundingPerVolume * data.netVolume / ONE;
        data.cumulativeFundingPerVolume = data.cumulativeFundingPerVolume.addUnchecked(diffFundingPerVolume);
    }

    function _getTradersPnl(Data memory data) internal pure {
        data.tradersPnl = -(DpmmPower.calculateCost(
            data.theoreticalPrice, data.k, data.netVolume, -data.netVolume
        ) + data.netCost);
    }

    function _getInitialMarginRequired(Data memory data) internal pure {
        data.maintenanceMarginPerVolume = data.theoreticalPrice * data.maintenanceMarginRatio / ONE;
        data.initialMarginPerVolume = data.maintenanceMarginPerVolume * data.initialMarginRatio / data.maintenanceMarginRatio;
        data.initialMarginRequired = data.netVolume.abs() * data.initialMarginPerVolume / ONE;
    }

    function _getRemoveLiquidityPenalty(
        Data memory data,
        int256 liquidity,
        int256 removedLiquidity
    ) internal pure {
        int256 newK = DpmmPower.calculateK(
            data.alpha, data.theoreticalPrice, liquidity - removedLiquidity
        );
        int256 newTradersPnl = -(DpmmPower.calculateCost(
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
