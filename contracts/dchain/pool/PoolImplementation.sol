// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../symbol/ISymbolManager.sol';
import '../../oracle/IOracle.sol';
import './IPool.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '../../library/Bytes32Map.sol';
import '../../library/SafeMath.sol';
import './PoolStorage.sol';

contract PoolImplementation is PoolStorage {

    using Bytes32Map for mapping(uint8 => bytes32);
    using SafeMath for uint256;
    using SafeMath for int256;

    error InvalidSignature();
    error InvalidRequestId();
    error InsufficientLiquidity();
    error InvalidPTokenId();
    error InsufficientMargin();
    error NoMaintenanceMarginRequired();
    error CanNotLiquidate();

    event CallbackAddLiquidity(
        uint256 requestId,
        uint256 lTokenId,
        uint256 liquidity,
        uint256 totalLiquidity,
        int256  cumulativePnlOnEngine
    );

    event CallbackRemoveLiquidity(
        uint256 requestId,
        uint256 lTokenId,
        uint256 liquidity,
        uint256 totalLiquidity,
        int256  cumulativePnlOnEngine,
        uint256 bAmount
    );

    event CallbackRemoveMargin(
        uint256 requestId,
        uint256 pTokenId,
        uint256 requiredMargin,
        int256  cumulativePnlOnEngine,
        uint256 bAmount
    );

    event CallbackLiquidate(
        uint256 requestId,
        uint256 pTokenId,
        int256  cumulativePnlOnEngine
    );

    uint8 constant S_TOTALLIQUIDITY            = 1;
    uint8 constant S_LPSPNL                    = 2;
    uint8 constant S_CUMULATIVEPNLPERLIQUIDITY = 3;
    uint8 constant S_PROTOCOLFEE               = 4;

    uint8 constant I_LASTCUMULATIVEPNLONVAULT  = 1;

    uint8 constant D_REQUESTID                 = 1;
    uint8 constant D_CUMULATIVEPNL             = 2;
    uint8 constant D_LIQUIDITY                 = 3;
    uint8 constant D_CUMULATIVEPNLPERLIQUIDITY = 4;
    uint8 constant D_LIQUIDATED                = 5;

    int256 constant ONE = 1e18;

    ISymbolManager internal immutable symbolManager;
    IOracle        internal immutable oracle;
    address        internal immutable eventSigner;
    int256         internal immutable initialMarginMultiplier;
    int256         internal immutable protocolFeeCollectRatio;

    constructor (
        address symbolManager_,
        address oracle_,
        address eventSigner_,
        int256 initialMarginMultiplier_,
        int256 protocolFeeCollectRatio_
    ) {
        symbolManager = ISymbolManager(symbolManager_);
        oracle = IOracle(oracle_);
        eventSigner = eventSigner_;
        initialMarginMultiplier = initialMarginMultiplier_;
        protocolFeeCollectRatio = protocolFeeCollectRatio_;
    }

    //================================================================================
    // Getters
    //================================================================================

    function getPoolParam() external view returns (IPool.PoolParam memory p) {
        p.symbolManager = address(symbolManager);
        p.oracle = address(oracle);
        p.eventSigner = eventSigner;
        p.initialMarginMultiplier = initialMarginMultiplier;
        p.protocolFeeCollectRatio = protocolFeeCollectRatio;
    }

    function getPoolState() external view returns (IPool.PoolState memory s) {
        s.totalLiquidity = _states.getInt(S_TOTALLIQUIDITY);
        s.lpsPnl = _states.getInt(S_LPSPNL);
        s.cumulativePnlPerLiquidity = _states.getInt(S_CUMULATIVEPNLPERLIQUIDITY);
        s.protocolFee = _states.getInt(S_PROTOCOLFEE);
    }

    function getChainState(uint88 chainId) external view returns (IPool.ChainState memory s) {
        s.lastCumulativePnlOnVault = _iStates[chainId].getInt(I_LASTCUMULATIVEPNLONVAULT);
    }

    function getLpState(uint256 lTokenId) external view returns (IPool.LpState memory s) {
        s.requestId = _dStates[lTokenId].getUint(D_REQUESTID);
        s.cumulativePnl = _dStates[lTokenId].getInt(D_CUMULATIVEPNL);
        s.liquidity = _dStates[lTokenId].getInt(D_LIQUIDITY);
        s.cumulativePnlPerLiquidity = _dStates[lTokenId].getInt(D_CUMULATIVEPNLPERLIQUIDITY);
    }

    function getTdState(uint256 pTokenId) external view returns (IPool.TdState memory s) {
        s.requestId = _dStates[pTokenId].getUint(D_REQUESTID);
        s.cumulativePnl = _dStates[pTokenId].getInt(D_CUMULATIVEPNL);
        s.liquidated = _dStates[pTokenId].getBool(D_LIQUIDATED);
    }

    //================================================================================
    // Interactions
    //================================================================================

    function addLiquidity(bytes memory eventData, bytes memory eventSig, IOracle.Signature[] memory signatures) external _reentryLock_ {
        _verifyEventData(eventData, eventSig);
        oracle.updateOffchainValues(signatures);
        IPool.VarOnAddLiquidity memory v = abi.decode(eventData, (IPool.VarOnAddLiquidity));
        _updateRequestId(v.lTokenId, v.requestId);
        _addLiquidity(v);
    }

    function removeLiquidity(bytes memory eventData, bytes memory eventSig, IOracle.Signature[] memory signatures) external _reentryLock_ {
        _verifyEventData(eventData, eventSig);
        oracle.updateOffchainValues(signatures);
        IPool.VarOnRemoveLiquidity memory v = abi.decode(eventData, (IPool.VarOnRemoveLiquidity));
        _updateRequestId(v.lTokenId, v.requestId);
        _removeLiquidity(v);
    }

    function removeMargin(bytes memory eventData, bytes memory eventSig, IOracle.Signature[] memory signatures) external _reentryLock_ {
        _verifyEventData(eventData, eventSig);
        oracle.updateOffchainValues(signatures);
        IPool.VarOnRemoveMargin memory v = abi.decode(eventData, (IPool.VarOnRemoveMargin));
        _updateRequestId(v.pTokenId, v.requestId);
        _removeMargin(v);
    }

    function trade(bytes memory eventData, bytes memory eventSig, IOracle.Signature[] memory signatures) external _reentryLock_ {
        _verifyEventData(eventData, eventSig);
        oracle.updateOffchainValues(signatures);
        IPool.VarOnTrade memory v = abi.decode(eventData, (IPool.VarOnTrade));
        _updateRequestId(v.pTokenId, v.requestId);
        _trade(v);
    }

    function liquidate(bytes memory eventData, bytes memory eventSig, IOracle.Signature[] memory signatures) external _reentryLock_ {
        _verifyEventData(eventData, eventSig);
        oracle.updateOffchainValues(signatures);
        IPool.VarOnLiquidate memory v = abi.decode(eventData, (IPool.VarOnLiquidate));
        _updateRequestId(v.pTokenId, v.requestId);
        _liquidate(v);
    }

    function tradeAndRemoveMargin(bytes memory eventData, bytes memory eventSig, IOracle.Signature[] memory signatures) external _reentryLock_ {
        _verifyEventData(eventData, eventSig);
        oracle.updateOffchainValues(signatures);
        IPool.VarOnTradeAndRemoveMargin memory v = abi.decode(eventData, (IPool.VarOnTradeAndRemoveMargin));
        _updateRequestId(v.pTokenId, v.requestId);
        _tradeAndRemoveMargin(v);
    }

    //================================================================================
    // Internal Interactions
    //================================================================================

    function _addLiquidity(IPool.VarOnAddLiquidity memory v) internal {
        Data memory data = _getData(v.lTokenId, true);

        if (data.totalLiquidity > 0) {
            ISymbolManager.SettlementOnAddLiquidity memory s =
                symbolManager.settleSymbolsOnAddLiquidity(data.totalLiquidity + data.lpsPnl);

            int256 undistributedPnl = s.funding - s.diffTradersPnl + _updateCumulativePnlOnVault(v.lTokenId, v.cumulativePnlOnVault);
            _settleUndistributedPnl(data, undistributedPnl);
        }

        _settleLp(data);

        int256 pnl = data.cumulativePnl.minusUnchecked(v.lastCumulativePnlOnEngine);
        int256 newLiquidity = SafeMath.max(v.liquidity.utoi() + pnl, int256(0));
        data.totalLiquidity += newLiquidity - data.lpLiquidity;
        data.lpLiquidity = newLiquidity;
        data.lpsPnl -= pnl;

        _saveData(data, v.lTokenId, true);

        emit CallbackAddLiquidity(
            v.requestId,
            v.lTokenId,
            data.lpLiquidity.itou(),
            data.totalLiquidity.itou(),
            data.cumulativePnl
        );
    }

    function _removeLiquidity(IPool.VarOnRemoveLiquidity memory v) internal {
        Data memory data = _getData(v.lTokenId, true);

        int256 removedLiquidity = data.lpLiquidity - v.liquidity.utoi();
        ISymbolManager.SettlementOnRemoveLiquidity memory s =
            symbolManager.settleSymbolsOnRemoveLiquidity(data.totalLiquidity + data.lpsPnl, removedLiquidity);

        int256 undistributedPnl = s.funding - s.diffTradersPnl + s.removeLiquidityPenalty
                                + _updateCumulativePnlOnVault(v.lTokenId, v.cumulativePnlOnVault);
        _settleUndistributedPnl(data, undistributedPnl);

        data.cumulativePnl = data.cumulativePnl.minusUnchecked(s.removeLiquidityPenalty);
        _settleLp(data);

        int256 pnl = data.cumulativePnl.minusUnchecked(v.lastCumulativePnlOnEngine);
        int256 newLiquidity = v.liquidity == 0 ? int256(0) : SafeMath.max(v.liquidity.utoi() + pnl, int256(0));
        data.totalLiquidity += newLiquidity - data.lpLiquidity;
        data.lpLiquidity = newLiquidity;
        data.lpsPnl -= pnl;

        if ((data.totalLiquidity + data.lpsPnl) * ONE < s.initialMarginRequired * initialMarginMultiplier) {
            revert InsufficientLiquidity();
        }

        _saveData(data, v.lTokenId, true);

        emit CallbackRemoveLiquidity(
            v.requestId,
            v.lTokenId,
            data.lpLiquidity.itou(),
            data.totalLiquidity.itou(),
            data.cumulativePnl,
            v.bAmount
        );
    }

    function _removeMargin(IPool.VarOnRemoveMargin memory v) internal {
        Data memory data = _getData(v.pTokenId, false);

        ISymbolManager.SettlementOnRemoveMargin memory s =
            symbolManager.settleSymbolsOnRemoveMargin(v.pTokenId, data.totalLiquidity + data.lpsPnl);

        int256 undistributedPnl = s.funding - s.diffTradersPnl + _updateCumulativePnlOnVault(v.pTokenId, v.cumulativePnlOnVault);
        _settleUndistributedPnl(data, undistributedPnl);

        data.cumulativePnl = data.cumulativePnl.minusUnchecked(s.traderFunding);

        int256 pnl = data.cumulativePnl.minusUnchecked(v.lastCumulativePnlOnEngine);
        int256 requiredMargin = SafeMath.max(s.traderInitialMarginRequired - s.traderPnl, int256(0));
        if (v.margin.utoi() + pnl < requiredMargin) {
            revert InsufficientMargin();
        }

        _saveData(data, v.pTokenId, false);

        emit CallbackRemoveMargin(
            v.requestId,
            v.pTokenId,
            requiredMargin.itou(),
            data.cumulativePnl,
            v.bAmount
        );
    }

    function _trade(IPool.VarOnTrade memory v) internal {
        Data memory data = _getData(v.pTokenId, false);

        ISymbolManager.SettlementOnTrade memory s = symbolManager.settleSymbolsOnTrade(
            v.symbolId,
            v.pTokenId,
            data.totalLiquidity + data.lpsPnl,
            v.tradeParams
        );

        int256 collect = s.tradeFee * protocolFeeCollectRatio / ONE;
        _states.set(S_PROTOCOLFEE, _states.getInt(S_PROTOCOLFEE) + collect);

        int256 undistributedPnl = s.funding - s.diffTradersPnl + s.tradeFee - collect + s.tradeRealizedCost
                                + _updateCumulativePnlOnVault(v.pTokenId, v.cumulativePnlOnVault);
        _settleUndistributedPnl(data, undistributedPnl);

        data.cumulativePnl = data.cumulativePnl.minusUnchecked(s.traderFunding + s.tradeFee + s.tradeRealizedCost);

        int256 pnl = data.cumulativePnl.minusUnchecked(v.lastCumulativePnlOnEngine);
        int256 requiredMargin = s.traderInitialMarginRequired - s.traderPnl;
        if (v.margin.utoi() + pnl < requiredMargin) {
            revert InsufficientMargin();
        }

        _saveData(data, v.pTokenId, false);
    }

    function _liquidate(IPool.VarOnLiquidate memory v) internal {
        Data memory data = _getData(v.pTokenId, false);

        ISymbolManager.SettlementOnLiquidate memory s = symbolManager.settleSymbolsOnLiquidate(
            v.pTokenId, data.totalLiquidity + data.lpsPnl
        );

        int256 undistributedPnl = s.funding - s.diffTradersPnl + s.tradeRealizedCost
                                + _updateCumulativePnlOnVault(v.pTokenId, v.cumulativePnlOnVault);
        _settleUndistributedPnl(data, undistributedPnl);

        if (s.traderMaintenanceMarginRequired <= 0) {
            revert NoMaintenanceMarginRequired();
        }

        data.cumulativePnl = data.cumulativePnl.minusUnchecked(s.traderFunding);

        int256 availableMargin = v.margin.utoi() + data.cumulativePnl.minusUnchecked(v.lastCumulativePnlOnEngine);
        if (availableMargin + s.traderPnl > s.traderMaintenanceMarginRequired) {
            revert CanNotLiquidate();
        }

        data.cumulativePnl = data.cumulativePnl.minusUnchecked(s.tradeRealizedCost);

        _saveData(data, v.pTokenId, false);
        _dStates[v.pTokenId].set(D_LIQUIDATED, true);

        emit CallbackLiquidate(
            v.requestId,
            v.pTokenId,
            data.cumulativePnl
        );
    }

    function _tradeAndRemoveMargin(IPool.VarOnTradeAndRemoveMargin memory v) internal {
        _trade(IPool.VarOnTrade({
            requestId: v.requestId,
            pTokenId: v.pTokenId,
            margin: v.margin,
            lastCumulativePnlOnEngine: v.lastCumulativePnlOnEngine,
            cumulativePnlOnVault: v.cumulativePnlOnVault,
            symbolId: v.symbolId,
            tradeParams: v.tradeParams
        }));
        _removeMargin(IPool.VarOnRemoveMargin({
            requestId: v.requestId,
            pTokenId: v.pTokenId,
            margin: v.margin,
            lastCumulativePnlOnEngine: v.lastCumulativePnlOnEngine,
            cumulativePnlOnVault: v.cumulativePnlOnVault,
            bAmount: v.bAmount
        }));
    }

    //================================================================================
    // Internals
    //================================================================================

    struct Data {
        // pool states
        int256 totalLiquidity;
        int256 lpsPnl;
        int256 cumulativePnlPerLiquidity;
        // lp/td states
        int256 lpLiquidity;
        int256 lpCumulativePnlPerLiqudity;
        int256 cumulativePnl;
    }

    function _verifyEventData(bytes memory eventData, bytes memory signature) internal view {
        bytes32 hash = ECDSA.toEthSignedMessageHash(keccak256(eventData));
        if (ECDSA.recover(hash, signature) != eventSigner) {
            revert InvalidSignature();
        }
    }

    function _getData(uint256 dTokenId, bool isLp) internal view returns (Data memory data) {
        data.totalLiquidity = _states.getInt(S_TOTALLIQUIDITY);
        data.lpsPnl = _states.getInt(S_LPSPNL);
        data.cumulativePnlPerLiquidity = _states.getInt(S_CUMULATIVEPNLPERLIQUIDITY);
        if (isLp) {
            data.lpLiquidity = _dStates[dTokenId].getInt(D_LIQUIDITY);
            data.lpCumulativePnlPerLiqudity = _dStates[dTokenId].getInt(D_CUMULATIVEPNLPERLIQUIDITY);
        } else {
            if (_dStates[dTokenId].getBool(D_LIQUIDATED)) {
                revert InvalidPTokenId();
            }
        }
        data.cumulativePnl = _dStates[dTokenId].getInt(D_CUMULATIVEPNL);
    }

    function _saveData(Data memory data, uint256 dTokenId, bool isLp) internal {
        if (isLp) {
            _states.set(S_TOTALLIQUIDITY, data.totalLiquidity);
            _dStates[dTokenId].set(D_LIQUIDITY, data.lpLiquidity);
            _dStates[dTokenId].set(D_CUMULATIVEPNLPERLIQUIDITY, data.lpCumulativePnlPerLiqudity);
        }
        _states.set(S_LPSPNL, data.lpsPnl);
        _states.set(S_CUMULATIVEPNLPERLIQUIDITY, data.cumulativePnlPerLiquidity);
        _dStates[dTokenId].set(D_CUMULATIVEPNL, data.cumulativePnl);
    }

    function _updateRequestId(uint256 dTokenId, uint256 requestId) internal {
        uint256 lastRequestId = _dStates[dTokenId].getUint(D_REQUESTID);
        if (requestId <= lastRequestId) {
            revert InvalidRequestId();
        }
        _dStates[dTokenId].set(D_REQUESTID, requestId);
    }

    function _getChainIdFromDTokenId(uint256 dTokenId) internal pure returns (uint88) {
        return uint88(dTokenId >> 160);
    }

    function _updateCumulativePnlOnVault(uint256 dTokenId, int256 cumulativePnlOnVault) internal returns (int256 undistributedPnl) {
        uint88 chainId = _getChainIdFromDTokenId(dTokenId);
        int256 lastCumulativePnlOnVault = _iStates[chainId].getInt(I_LASTCUMULATIVEPNLONVAULT);
        if (lastCumulativePnlOnVault != cumulativePnlOnVault) {
            undistributedPnl = cumulativePnlOnVault.minusUnchecked(lastCumulativePnlOnVault);
            _iStates[chainId].set(I_LASTCUMULATIVEPNLONVAULT, cumulativePnlOnVault);
        }
    }

    function _settleLp(Data memory data) internal pure {
        if (data.lpLiquidity > 0) {
            int256 diff = data.cumulativePnlPerLiquidity.minusUnchecked(data.lpCumulativePnlPerLiqudity);
            data.cumulativePnl = data.cumulativePnl.addUnchecked(diff * data.lpLiquidity / ONE);
        }
        data.lpCumulativePnlPerLiqudity = data.cumulativePnlPerLiquidity;
    }

    function _settleUndistributedPnl(Data memory data, int256 undistributedPnl) internal pure {
        data.lpsPnl += undistributedPnl;
        int256 diff = undistributedPnl * ONE / data.totalLiquidity;
        data.cumulativePnlPerLiquidity = data.cumulativePnlPerLiquidity.addUnchecked(diff);
    }

}
