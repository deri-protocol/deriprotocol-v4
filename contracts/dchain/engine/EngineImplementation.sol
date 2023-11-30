// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../symbol/ISymbolManager.sol';
import '../../oracle/IOracle.sol';
import './IEngine.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '../../library/Bytes32Map.sol';
import '../../library/SafeMath.sol';
import './EngineStorage.sol';

contract EngineImplementation is EngineStorage {

    using Bytes32Map for mapping(uint8 => bytes32);
    using SafeMath for uint256;
    using SafeMath for int256;

    error InvalidSignature();
    error InvalidRequestId();
    error InsufficientLiquidity();
    error DTokenLiquidated();
    error InsufficientMargin();
    error NoMaintenanceMarginRequired();
    error CanNotLiquidate();

    event ExecuteUpdateLiquidity(
        uint256 requestId,
        uint256 lTokenId,
        uint256 liquidity,
        uint256 totalLiquidity,
        int256  cumulativePnlOnEngine,
        uint256 bAmountToRemove
    );

    event ExecuteRemoveMargin(
        uint256 requestId,
        uint256 pTokenId,
        uint256 requiredMargin,
        int256  cumulativePnlOnEngine,
        uint256 bAmount
    );

    event ExecuteLiquidate(
        uint256 requestId,
        uint256 pTokenId,
        int256  cumulativePnlOnEngine
    );

    uint8 constant S_TOTALLIQUIDITY            = 1; // total liquidity
    uint8 constant S_LPSPNL                    = 2; // total lp's pnl
    uint8 constant S_CUMULATIVEPNLPERLIQUIDITY = 3; // cumulative pnl per liquidity
    uint8 constant S_PROTOCOLFEE               = 4; // total protocol fee collected

    uint8 constant I_LASTCUMULATIVEPNLONGATEWAY = 1; // last cumulative pnl on specific i-chain gateway
    uint8 constant I_LASTGATEWAYREQUESTID       = 2; // last gateway request id on specific i-chain gateway
    uint8 constant I_PROTOCOLFEE                = 3; // protocol fee collected for specific i-chain

    uint8 constant D_REQUESTID                 = 1; // Lp/Trader request id
    uint8 constant D_CUMULATIVEPNL             = 2; // Lp/Trader cumulative pnl
    uint8 constant D_LIQUIDITY                 = 3; // Lp liquidity
    uint8 constant D_CUMULATIVEPNLPERLIQUIDITY = 4; // Lp cumulative pnl per liquidity
    uint8 constant D_LIQUIDATED                = 5; // Is trader liquidated

    int256 constant ONE = 1e18;

    ISymbolManager internal immutable symbolManager;
    IOracle        internal immutable oracle;
    address        internal immutable iChainEventSigner;
    int256         internal immutable initialMarginMultiplier;
    int256         internal immutable protocolFeeCollectRatio;

    constructor (
        address symbolManager_,
        address oracle_,
        address iChainEventSigner_,
        int256 initialMarginMultiplier_,
        int256 protocolFeeCollectRatio_
    ) {
        symbolManager = ISymbolManager(symbolManager_);
        oracle = IOracle(oracle_);
        iChainEventSigner = iChainEventSigner_;
        initialMarginMultiplier = initialMarginMultiplier_;
        protocolFeeCollectRatio = protocolFeeCollectRatio_;
    }

    //================================================================================
    // Getters
    //================================================================================

    function getEngineState() external view returns (IEngine.EngineState memory s) {
        s.symbolManager = address(symbolManager);
        s.oracle = address(oracle);
        s.iChainEventSigner = iChainEventSigner;
        s.initialMarginMultiplier = initialMarginMultiplier;
        s.protocolFeeCollectRatio = protocolFeeCollectRatio;
        s.totalLiquidity = _states.getInt(S_TOTALLIQUIDITY);
        s.lpsPnl = _states.getInt(S_LPSPNL);
        s.cumulativePnlPerLiquidity = _states.getInt(S_CUMULATIVEPNLPERLIQUIDITY);
        s.protocolFee = _states.getUint(S_PROTOCOLFEE);
    }

    function getChainState(uint88 chainId) external view returns (IEngine.ChainState memory s) {
        s.lastCumulativePnlOnGateway = _iStates[chainId].getInt(I_LASTCUMULATIVEPNLONGATEWAY);
        s.lastGatewayRequestId = _iStates[chainId].getUint(I_LASTGATEWAYREQUESTID);
        s.protocolFee = _iStates[chainId].getUint(I_PROTOCOLFEE);
    }

    function getLpState(uint256 lTokenId) external view returns (IEngine.LpState memory s) {
        s.requestId = _dStates[lTokenId].getUint(D_REQUESTID);
        s.cumulativePnl = _dStates[lTokenId].getInt(D_CUMULATIVEPNL);
        s.liquidity = _dStates[lTokenId].getInt(D_LIQUIDITY);
        s.cumulativePnlPerLiquidity = _dStates[lTokenId].getInt(D_CUMULATIVEPNLPERLIQUIDITY);
    }

    function getTdState(uint256 pTokenId) external view returns (IEngine.TdState memory s) {
        s.requestId = _dStates[pTokenId].getUint(D_REQUESTID);
        s.cumulativePnl = _dStates[pTokenId].getInt(D_CUMULATIVEPNL);
        s.liquidated = _dStates[pTokenId].getBool(D_LIQUIDATED);
    }

    //================================================================================
    // Interactions
    //================================================================================

    function updateLiquidity(bytes memory eventData, bytes memory eventSig, IOracle.Signature[] memory signatures) external _reentryLock_ {
        _verifyEventData(eventData, eventSig);
        oracle.updateOffchainValues(signatures);
        IEngine.VarOnUpdateLiquidity memory v = abi.decode(eventData, (IEngine.VarOnUpdateLiquidity));
        _updateUserRequestId(v.lTokenId, v.requestId);
        uint256 curLiquidity = _dStates[v.lTokenId].getInt(D_LIQUIDITY).itou();
        // Depends on liquidity change, call addLiquidity or removeLiquidity logic
        if (v.liquidity >= curLiquidity) {
            _addLiquidity(v);
        } else if (v.liquidity < curLiquidity) {
            _removeLiquidity(v);
        }
    }

    function removeMargin(bytes memory eventData, bytes memory eventSig, IOracle.Signature[] memory signatures) external _reentryLock_ {
        _verifyEventData(eventData, eventSig);
        oracle.updateOffchainValues(signatures);
        IEngine.VarOnRemoveMargin memory v = abi.decode(eventData, (IEngine.VarOnRemoveMargin));
        _updateUserRequestId(v.pTokenId, v.requestId);
        _removeMargin(v);
    }

    function trade(bytes memory eventData, bytes memory eventSig, IOracle.Signature[] memory signatures) external _reentryLock_ {
        _verifyEventData(eventData, eventSig);
        oracle.updateOffchainValues(signatures);
        IEngine.VarOnTrade memory v;
        (
            v.requestId,
            v.pTokenId,
            v.realMoneyMargin,
            v.lastCumulativePnlOnEngine,
            v.cumulativePnlOnGateway,
            v.symbolId,
            v.tradeParams
        ) = abi.decode(eventData, (uint256, uint256, uint256, int256, int256, bytes32, int256[]));
        _updateUserRequestId(v.pTokenId, v.requestId);
        _trade(v);
    }

    function liquidate(bytes memory eventData, bytes memory eventSig, IOracle.Signature[] memory signatures) external _reentryLock_ {
        _verifyEventData(eventData, eventSig);
        oracle.updateOffchainValues(signatures);
        IEngine.VarOnLiquidate memory v = abi.decode(eventData, (IEngine.VarOnLiquidate));
        _updateUserRequestId(v.pTokenId, v.requestId);
        _liquidate(v);
    }

    function tradeAndRemoveMargin(bytes memory eventData, bytes memory eventSig, IOracle.Signature[] memory signatures) external _reentryLock_ {
        _verifyEventData(eventData, eventSig);
        oracle.updateOffchainValues(signatures);
        IEngine.VarOnTradeAndRemoveMargin memory v;
        (
            v.requestId,
            v.pTokenId,
            v.realMoneyMargin,
            v.lastCumulativePnlOnEngine,
            v.cumulativePnlOnGateway,
            v.bAmount,
            v.symbolId,
            v.tradeParams
        ) = abi.decode(eventData, (uint256, uint256, uint256, int256, int256, uint256, bytes32, int256[]));
        _updateUserRequestId(v.pTokenId, v.requestId);
        _tradeAndRemoveMargin(v);
    }

    //================================================================================
    // Terminations when decoupling i-chain
    //================================================================================

    // @notice Terminate traders' positions when corresponding i-chain become permanently inactive
    function terminateTds(uint256[] memory pTokenIds, IOracle.Signature[] memory signatures) external _onlyAdmin_ {
        oracle.updateOffchainValues(signatures);
        for (uint256 i = 0; i < pTokenIds.length; i++) {
            _terminateTd(pTokenIds[i]);
        }
    }

    // @notice Terminate Lps when corresponding i-chain become permanently inactive
    function terminateLps(uint256[] memory lTokenIds, IOracle.Signature[] memory signatures) external _onlyAdmin_ {
        oracle.updateOffchainValues(signatures);
        for (uint256 i = 0; i < lTokenIds.length; i++) {
            _terminateLp(lTokenIds[i]);
        }
    }

    // @notice Settle i-chain Pnl after termination, when i-chain become permanently inactive
    // @param terminationPnl Pnl calculated during termination for all Lp and Td
    // @param totalB0Amount Total b0Amount recorded on i-chain for all Lp and Td
    // @param vault0B0Amount b0Amount in i-chain's vault0 reserve
    // @param iouAmount IOU amount issue on i-chain
    function settleIChainPnlAfterTermination(
        int256 terminationPnl,
        int256 totalB0Amount,
        int256 vault0B0Amount,
        int256 iouAmount
    ) external _onlyAdmin_ {
        int256 totalLiquidity = _states.getInt(S_TOTALLIQUIDITY);
        int256 lpsPnl = _states.getInt(S_LPSPNL);
        int256 cumulativePnlPerLiquidity = _states.getInt(S_CUMULATIVEPNLPERLIQUIDITY);

        int256 pnl = terminationPnl + totalB0Amount - vault0B0Amount + iouAmount;
        lpsPnl += pnl;
        cumulativePnlPerLiquidity = cumulativePnlPerLiquidity.addUnchecked(
            pnl * ONE / totalLiquidity
        );

        _states.set(S_LPSPNL, lpsPnl);
        _states.set(S_CUMULATIVEPNLPERLIQUIDITY, cumulativePnlPerLiquidity);
    }

    //================================================================================
    // Internal Interactions
    //================================================================================

    function _addLiquidity(IEngine.VarOnUpdateLiquidity memory v) internal {
        Data memory data = _getData(v.lTokenId, true);

        if (data.totalLiquidity > 0) {
            ISymbolManager.SettlementOnAddLiquidity memory s =
                symbolManager.settleSymbolsOnAddLiquidity(data.totalLiquidity + data.lpsPnl);

            int256 undistributedPnl = s.funding - s.diffTradersPnl + _updateCumulativePnlOnGateway(
                v.requestId, v.lTokenId, v.cumulativePnlOnGateway
            );
            _settleUndistributedPnl(data, undistributedPnl);
        }

        _settleLp(data);

        int256 pnl = data.cumulativePnl.minusUnchecked(v.lastCumulativePnlOnEngine);
        int256 newLiquidity = SafeMath.max(v.liquidity.utoi() + pnl, int256(0));
        data.totalLiquidity += newLiquidity - data.lpLiquidity;
        data.lpLiquidity = newLiquidity;
        data.lpsPnl -= pnl;

        _saveData(data, v.lTokenId, true);

        emit ExecuteUpdateLiquidity(
            v.requestId,
            v.lTokenId,
            data.lpLiquidity.itou(),
            data.totalLiquidity.itou(),
            data.cumulativePnl,
            v.bAmountToRemove
        );
    }

    function _removeLiquidity(IEngine.VarOnUpdateLiquidity memory v) internal {
        Data memory data = _getData(v.lTokenId, true);

        int256 removedLiquidity = data.lpLiquidity - v.liquidity.utoi();
        ISymbolManager.SettlementOnRemoveLiquidity memory s =
            symbolManager.settleSymbolsOnRemoveLiquidity(data.totalLiquidity + data.lpsPnl, removedLiquidity);

        int256 undistributedPnl = s.funding - s.diffTradersPnl + s.removeLiquidityPenalty
                                + _updateCumulativePnlOnGateway(v.requestId, v.lTokenId, v.cumulativePnlOnGateway);
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

        emit ExecuteUpdateLiquidity(
            v.requestId,
            v.lTokenId,
            data.lpLiquidity.itou(),
            data.totalLiquidity.itou(),
            data.cumulativePnl,
            v.bAmountToRemove
        );
    }

    function _removeMargin(IEngine.VarOnRemoveMargin memory v) internal {
        Data memory data = _getData(v.pTokenId, false);

        ISymbolManager.SettlementOnRemoveMargin memory s =
            symbolManager.settleSymbolsOnRemoveMargin(v.pTokenId, data.totalLiquidity + data.lpsPnl);

        int256 undistributedPnl = s.funding - s.diffTradersPnl + _updateCumulativePnlOnGateway(
            v.requestId, v.pTokenId, v.cumulativePnlOnGateway
        );
        _settleUndistributedPnl(data, undistributedPnl);

        data.cumulativePnl = data.cumulativePnl.minusUnchecked(s.traderFunding);

        int256 requiredRealMoneyMargin;
        if (s.traderInitialMarginRequired > 0) {
            int256 realizedPnl = data.cumulativePnl.minusUnchecked(v.lastCumulativePnlOnEngine);
            requiredRealMoneyMargin = SafeMath.max(s.traderInitialMarginRequired - s.traderPnl, int256(0));
            if (v.realMoneyMargin.utoi() + realizedPnl < requiredRealMoneyMargin) {
                revert InsufficientMargin();
            }
        }

        _saveData(data, v.pTokenId, false);

        emit ExecuteRemoveMargin(
            v.requestId,
            v.pTokenId,
            requiredRealMoneyMargin.itou(),
            data.cumulativePnl,
            v.bAmount
        );
    }

    function _trade(IEngine.VarOnTrade memory v) internal {
        Data memory data = _getData(v.pTokenId, false);

        ISymbolManager.SettlementOnTrade memory s = symbolManager.settleSymbolsOnTrade(
            v.symbolId,
            v.pTokenId,
            data.totalLiquidity + data.lpsPnl,
            v.tradeParams
        );

        // Collect protocol fee
        int256 collect = s.tradeFee * protocolFeeCollectRatio / ONE;
        uint88 chainId = _getChainIdFromDTokenId(v.pTokenId);
        _states.set(S_PROTOCOLFEE, _states.getUint(S_PROTOCOLFEE) + collect.itou());
        _iStates[chainId].set(I_PROTOCOLFEE, _iStates[chainId].getUint(I_PROTOCOLFEE) + collect.itou());

        int256 undistributedPnl = s.funding - s.diffTradersPnl + s.tradeFee - collect + s.tradeRealizedCost
                                + _updateCumulativePnlOnGateway(v.requestId, v.pTokenId, v.cumulativePnlOnGateway);
        _settleUndistributedPnl(data, undistributedPnl);

        data.cumulativePnl = data.cumulativePnl.minusUnchecked(s.traderFunding + s.tradeFee + s.tradeRealizedCost);

        if (s.traderInitialMarginRequired > 0) {
            int256 realizedPnl = data.cumulativePnl.minusUnchecked(v.lastCumulativePnlOnEngine);
            int256 requiredRealMoneyMargin = s.traderInitialMarginRequired - s.traderPnl;
            if (v.realMoneyMargin.utoi() + realizedPnl < requiredRealMoneyMargin) {
                revert InsufficientMargin();
            }

            if ((data.totalLiquidity + data.lpsPnl) * ONE < s.initialMarginRequired * initialMarginMultiplier) {
                revert InsufficientLiquidity();
            }
        }

        _saveData(data, v.pTokenId, false);
    }

    function _liquidate(IEngine.VarOnLiquidate memory v) internal {
        Data memory data = _getData(v.pTokenId, false);

        ISymbolManager.SettlementOnLiquidate memory s = symbolManager.settleSymbolsOnLiquidate(
            v.pTokenId, data.totalLiquidity + data.lpsPnl
        );

        int256 undistributedPnl = s.funding - s.diffTradersPnl + s.tradeRealizedCost
                                + _updateCumulativePnlOnGateway(v.requestId, v.pTokenId, v.cumulativePnlOnGateway);
        _settleUndistributedPnl(data, undistributedPnl);

        data.cumulativePnl = data.cumulativePnl.minusUnchecked(s.traderFunding);

        int256 availableMargin = v.realMoneyMargin.utoi() + data.cumulativePnl.minusUnchecked(v.lastCumulativePnlOnEngine);
        if (availableMargin + s.traderPnl > s.traderMaintenanceMarginRequired) {
            revert CanNotLiquidate();
        }

        data.cumulativePnl = data.cumulativePnl.minusUnchecked(s.tradeRealizedCost);

        _saveData(data, v.pTokenId, false);
        _dStates[v.pTokenId].set(D_LIQUIDATED, true);

        emit ExecuteLiquidate(
            v.requestId,
            v.pTokenId,
            data.cumulativePnl
        );
    }

    function _tradeAndRemoveMargin(IEngine.VarOnTradeAndRemoveMargin memory v) internal {
        _trade(IEngine.VarOnTrade({
            requestId: v.requestId,
            pTokenId: v.pTokenId,
            realMoneyMargin: v.realMoneyMargin,
            lastCumulativePnlOnEngine: v.lastCumulativePnlOnEngine,
            cumulativePnlOnGateway: v.cumulativePnlOnGateway,
            symbolId: v.symbolId,
            tradeParams: v.tradeParams
        }));
        _removeMargin(IEngine.VarOnRemoveMargin({
            requestId: v.requestId,
            pTokenId: v.pTokenId,
            realMoneyMargin: v.realMoneyMargin,
            lastCumulativePnlOnEngine: v.lastCumulativePnlOnEngine,
            cumulativePnlOnGateway: v.cumulativePnlOnGateway,
            bAmount: v.bAmount
        }));
    }

    function _terminateTd(uint256 pTokenId) internal {
        Data memory data = _getData(pTokenId, false);

        ISymbolManager.SettlementOnLiquidate memory s = symbolManager.settleSymbolsOnLiquidate(
            pTokenId, data.totalLiquidity + data.lpsPnl
        );

        int256 undistributedPnl = s.funding - s.diffTradersPnl + s.tradeRealizedCost;
        _settleUndistributedPnl(data, undistributedPnl);

        data.cumulativePnl = data.cumulativePnl.minusUnchecked(s.traderFunding + s.tradeRealizedCost);

        _saveData(data, pTokenId, false);
        _dStates[pTokenId].set(D_LIQUIDATED, true);
    }

    function _terminateLp(uint256 lTokenId) internal {
        Data memory data = _getData(lTokenId, true);

        ISymbolManager.SettlementOnRemoveLiquidity memory s =
            symbolManager.settleSymbolsOnRemoveLiquidity(data.totalLiquidity + data.lpsPnl, data.lpLiquidity);

        int256 undistributedPnl = s.funding - s.diffTradersPnl + s.removeLiquidityPenalty;
        _settleUndistributedPnl(data, undistributedPnl);

        data.cumulativePnl = data.cumulativePnl.minusUnchecked(s.removeLiquidityPenalty);
        _settleLp(data);

        data.totalLiquidity -= data.lpLiquidity;
        data.lpLiquidity = 0;

        _saveData(data, lTokenId, true);
        _dStates[lTokenId].set(D_LIQUIDATED, true);
    }

    //================================================================================
    // Internals
    //================================================================================

    struct Data {
        // Engine states
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
        if (ECDSA.recover(hash, signature) != iChainEventSigner) {
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
        }
        if (_dStates[dTokenId].getBool(D_LIQUIDATED)) {
            revert DTokenLiquidated();
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

    function _updateUserRequestId(uint256 dTokenId, uint256 requestId) internal {
        uint128 userRequestId = uint128(requestId);
        uint128 lastUserRequestId = uint128(_dStates[dTokenId].getUint(D_REQUESTID));
        if (userRequestId <= lastUserRequestId) {
            revert InvalidRequestId();
        }
        _dStates[dTokenId].set(D_REQUESTID, uint256(userRequestId));
    }

    function _getChainIdFromDTokenId(uint256 dTokenId) internal pure returns (uint88) {
        return uint88(dTokenId >> 160);
    }

    function _updateCumulativePnlOnGateway(uint256 requestId, uint256 dTokenId, int256 cumulativePnlOnGateway)
    internal returns (int256 undistributedPnl)
    {
        uint88 chainId = _getChainIdFromDTokenId(dTokenId);
        uint256 gatewayRequestId = requestId >> 128;
        uint256 lastGatewayRequestId = _iStates[chainId].getUint(I_LASTGATEWAYREQUESTID);
        if (gatewayRequestId > lastGatewayRequestId) {
            _iStates[chainId].set(I_LASTGATEWAYREQUESTID, gatewayRequestId);

            int256 lastCumulativePnlOnGateway = _iStates[chainId].getInt(I_LASTCUMULATIVEPNLONGATEWAY);
            if (lastCumulativePnlOnGateway != cumulativePnlOnGateway) {
                undistributedPnl = cumulativePnlOnGateway.minusUnchecked(lastCumulativePnlOnGateway);
                _iStates[chainId].set(I_LASTCUMULATIVEPNLONGATEWAY, cumulativePnlOnGateway);
            }
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
