// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IPool.sol';
import '../interface/IOracle.sol';
import '../interface/ISymbolManager.sol';
import '../library/Bytes32Map.sol';
import '../library/SafeMath.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import './PoolStorage.sol';

contract PoolImplementation is PoolStorage {

    using Bytes32Map for mapping(uint8 => bytes32);
    using SafeMath for uint256;
    using SafeMath for int256;

    error InvalidLOrPTokenId();
    error InvalidStTokenId();
    error InvalidRequestId();
    error InconsistentState();
    error InsufficientLiquidity();
    error InsufficientMargin();
    error NoMaintenanceMarginRequired();
    error CanNotLiquidate();
    error OnlySelf();
    error InvalidSignature();

    event UpdatePoolParameter();
    event Error(bytes);
    event AddLiquidity(
        uint256 indexed requestId,
        uint256 indexed lTokenId,
        bytes32 indexed stTokenId,
        uint256 stPrice,
        uint256 stAmount
    );
    event RemoveLiquidity(
        uint256 indexed requestId,
        uint256 indexed lTokenId,
        bytes32 indexed stTokenId,
        uint256 stPrice,
        uint256 stAmount,
        int256 cumulativePnl
    );
    event RemoveMargin(
        uint256 indexed requestId,
        uint256 indexed pTokenId,
        bytes32 indexed stTokenId,
        uint256 stPrice,
        uint256 stAmount,
        int256 cumulativePnl,
        int256 cumulativeProtocolFee,
        int256 requiredMargin
    );
    event Trade(
        uint256 indexed requestId,
        uint256 indexed pTokenId,
        bytes32 indexed stTokenId,
        uint256 stPrice,
        uint256 stAmount,
        int256 cumulativePnl,
        int256 cumulativeProtocolFee,
        int256 requiredMargin
    );
    event Liquidate(
        uint256 indexed requestId,
        uint256 indexed pTokenId,
        bytes32 indexed stTokenId,
        uint256 stPrice,
        uint256 stAmount,
        int256 cumulativePnl,
        int256 cumulativeProtocolFee
    );
    event PostLiquidate(
        uint256 indexed requestId,
        uint256 indexed pTokenId,
        int256 cumulativePnl
    );

    uint8 constant S_SYMBOLMANAGER               = 1;
    uint8 constant S_ORACLE                      = 2;
    uint8 constant S_INITIALMARGINMULTIPLIER     = 3;
    uint8 constant S_PROTOCOLFEECOLLECTIONRATIO  = 4;
    uint8 constant S_EVENTDATASIGNER             = 5;
    uint8 constant S_LIQUIDITY                   = 6;
    uint8 constant S_LPSPNL                      = 7;
    uint8 constant S_CUMULATIVETIMEPERLIQUIDITY  = 8;
    uint8 constant S_CUMULATIVEPNLPERLIQUIDITY   = 9;
    uint8 constant S_LASTTIMESTAMP               = 10;

    uint8 constant ST_PRICE                      = 1;
    uint8 constant ST_TOTALAMOUNT                = 2;
    uint8 constant ST_CUMULATIVETIMEPERLIQUIDITY = 3;
    uint8 constant ST_CUMULATIVEPNLPERLIQUIDITY  = 4;
    uint8 constant ST_CUMULATIVETIMEPERTOKEN     = 5;
    uint8 constant ST_CUMULATIVEPNLPERTOKEN      = 6;

    uint8 constant SLP_LASTREQUESTID             = 1;
    uint8 constant SLP_STTOKENID                 = 2;
    uint8 constant SLP_STAMOUNT                  = 3;
    uint8 constant SLP_CUMULATIVETIME            = 4;
    uint8 constant SLP_CUMULATIVEPNL             = 5;
    uint8 constant SLP_CUMULATIVETIMEPERTOKEN    = 6;
    uint8 constant SLP_CUMULATIVEPNLPERTOKEN     = 7;
    uint8 constant SLP_LASTCUMULATIVEPNL         = 8;

    uint8 constant STD_LASTREQUESTID             = 1;
    uint8 constant STD_STTOKENID                 = 2;
    uint8 constant STD_STAMOUNT                  = 3;
    uint8 constant STD_CUMULATIVEPNL             = 4;
    uint8 constant STD_CUMULATIVEPROTOCOLFEE     = 5;

    uint8 constant ACTION_ADDLIQUIDITY           = 1;
    uint8 constant ACTION_REMOVELIQUIDITY        = 2;
    uint8 constant ACTION_TRADERWITHPOSTION      = 3;
    uint8 constant ACTION_TRADE                  = 4;
    uint8 constant ACTION_LIQUIDATE              = 5;
    uint8 constant ACTION_POSTLIQUIDATE          = 6;

    int256 constant ONE = 1e18;

    //================================================================================
    // Getters
    //================================================================================

    function getState() external view returns (bytes32[] memory s) {
        s = new bytes32[](10);
        s[0] = _states.getBytes32(S_SYMBOLMANAGER);
        s[1] = _states.getBytes32(S_ORACLE);
        s[2] = _states.getBytes32(S_INITIALMARGINMULTIPLIER);
        s[3] = _states.getBytes32(S_PROTOCOLFEECOLLECTIONRATIO);
        s[4] = _states.getBytes32(S_EVENTDATASIGNER);
        s[5] = _states.getBytes32(S_LIQUIDITY);
        s[6] = _states.getBytes32(S_LPSPNL);
        s[7] = _states.getBytes32(S_CUMULATIVETIMEPERLIQUIDITY);
        s[8] = _states.getBytes32(S_CUMULATIVEPNLPERLIQUIDITY);
        s[9] = _states.getBytes32(S_LASTTIMESTAMP);
    }

    function getStTokenState(bytes32 stTokenId) external view returns (bytes32[] memory s) {
        s = new bytes32[](6);
        s[0] = _stTokenStates[stTokenId].getBytes32(ST_PRICE);
        s[1] = _stTokenStates[stTokenId].getBytes32(ST_TOTALAMOUNT);
        s[2] = _stTokenStates[stTokenId].getBytes32(ST_CUMULATIVETIMEPERLIQUIDITY);
        s[3] = _stTokenStates[stTokenId].getBytes32(ST_CUMULATIVEPNLPERLIQUIDITY);
        s[4] = _stTokenStates[stTokenId].getBytes32(ST_CUMULATIVETIMEPERTOKEN);
        s[5] = _stTokenStates[stTokenId].getBytes32(ST_CUMULATIVEPNLPERTOKEN);
    }

    function getLpState(uint256 lTokenId) external view returns (bytes32[] memory s) {
        s = new bytes32[](8);
        s[0] = _lpStates[lTokenId].getBytes32(SLP_LASTREQUESTID);
        s[1] = _lpStates[lTokenId].getBytes32(SLP_STTOKENID);
        s[2] = _lpStates[lTokenId].getBytes32(SLP_STAMOUNT);
        s[3] = _lpStates[lTokenId].getBytes32(SLP_CUMULATIVETIME);
        s[4] = _lpStates[lTokenId].getBytes32(SLP_CUMULATIVEPNL);
        s[5] = _lpStates[lTokenId].getBytes32(SLP_CUMULATIVETIMEPERTOKEN);
        s[6] = _lpStates[lTokenId].getBytes32(SLP_CUMULATIVEPNLPERTOKEN);
        s[7] = _lpStates[lTokenId].getBytes32(SLP_LASTCUMULATIVEPNL);
    }

    function getTdState(uint256 pTokenId) external view returns (bytes32[] memory s) {
        s = new bytes32[](5);
        s[0] = _tdStates[pTokenId].getBytes32(STD_LASTREQUESTID);
        s[1] = _tdStates[pTokenId].getBytes32(STD_STTOKENID);
        s[2] = _tdStates[pTokenId].getBytes32(STD_STAMOUNT);
        s[3] = _tdStates[pTokenId].getBytes32(STD_CUMULATIVEPNL);
        s[4] = _tdStates[pTokenId].getBytes32(STD_CUMULATIVEPROTOCOLFEE);
    }

    //================================================================================
    // Setters
    //================================================================================

    function setPoolParameter(uint8 parameterId, bytes32 value) external _onlyAdmin_ {
        _states.set(parameterId, value);
        emit UpdatePoolParameter();
    }

    //================================================================================
    // Interactions
    //================================================================================

    function addLiquidity(bytes memory eventData, bytes memory eventSig, IOracle.Signature[] memory signatures) public _reentryLock_ {
        _verifyEventData(eventData, eventSig);
        IPool.VarOnAddLiquidity memory v;
        (
            v.requestId,
            v.lTokenId,
            v.stTokenId,
            v.stPrice,
            v.stAmount
        ) = abi.decode(eventData, (uint256, uint256, bytes32, uint256, uint256));
        try this._addLiquidity(v, signatures) {

        } catch (bytes memory e) {
            emit Error(e);
        }
    }

    function removeLiquidity(bytes memory eventData, bytes memory eventSig, IOracle.Signature[] memory signatures) public _reentryLock_ {
        _verifyEventData(eventData, eventSig);
        IPool.VarOnRemoveLiquidity memory v;
        (
            v.requestId,
            v.lTokenId,
            v.stTokenId,
            v.stPrice,
            v.stAmount
        ) = abi.decode(eventData, (uint256, uint256, bytes32, uint256, uint256));
        try this._removeLiquidity(v, signatures) {

        } catch (bytes memory e) {
            emit Error(e);
        }
    }

    function removeMargin(bytes memory eventData, bytes memory eventSig, IOracle.Signature[] memory signatures) public _reentryLock_ {
        _verifyEventData(eventData, eventSig);
        IPool.VarOnRemoveMargin memory v;
        (
            v.requestId,
            v.pTokenId,
            v.stTokenId,
            v.stPrice,
            v.stAmount,
            v.lastCumulativePnl
        ) = abi.decode(eventData, (uint256, uint256, bytes32, uint256, uint256, int256));
        try this._removeMargin(v, signatures) {

        } catch (bytes memory e) {
            emit Error(e);
        }
    }

    function trade(bytes memory eventData, bytes memory eventSig, IOracle.Signature[] memory signatures) public _reentryLock_ {
        _verifyEventData(eventData, eventSig);
        IPool.VarOnTrade memory v;
        (
            v.requestId,
            v.pTokenId,
            v.stTokenId,
            v.stPrice,
            v.stAmount,
            v.lastCumulativePnl,
            v.symbolId,
            v.tradeParams
        ) = abi.decode(eventData, (uint256, uint256, bytes32, uint256, uint256, int256, bytes32, int256[]));
        try this._trade(v, signatures) {

        } catch (bytes memory e) {
            emit Error(e);
        }
    }

    function liquidate(bytes memory eventData, bytes memory eventSig, IOracle.Signature[] memory signatures) public _reentryLock_ {
        _verifyEventData(eventData, eventSig);
        IPool.VarOnLiquidate memory v;
        (
            v.requestId,
            v.pTokenId,
            v.stTokenId,
            v.stPrice,
            v.stAmount,
            v.lastCumulativePnl
        ) = abi.decode(eventData, (uint256, uint256, bytes32, uint256, uint256, int256));
        try this._liquidate(v, signatures) {

        } catch (bytes memory e) {
            emit Error(e);
        }
    }

    function postLiquidate(bytes memory eventData, bytes memory eventSig) public _reentryLock_ {
        _verifyEventData(eventData, eventSig);
        IPool.VarOnPostLiquidate memory v;
        (
            v.requestId,
            v.pTokenId,
            v.lastCumulativePnl
        ) = abi.decode(eventData, (uint256, uint256, int256));
        try this._postLiquidate(v) {

        } catch (bytes memory e) {
            emit Error(e);
        }
    }

    //================================================================================
    // Internals
    //================================================================================

    function _verifyEventData(bytes memory eventData, bytes memory eventSig) internal view {
        bytes32 hash = ECDSA.toEthSignedMessageHash(keccak256(eventData));
        if (ECDSA.recover(hash, eventSig) != _states.getAddress(S_EVENTDATASIGNER)) {
            revert InvalidSignature();
        }
    }

    struct Data {
        // pool states
        int256  liquidity;
        int256  lpsPnl;
        int256  cumulativePnlPerLiquidity;
        int256  cumulativeTimePerLiquidity;
        int256  lastTimestamp;
        // stToken states
        int256  preStPrice;
        int256  preStTotalAmount;
        int256  stCumulativeTimePerLiquidity;
        int256  stCumulativePnlPerLiquidity;
        int256  stCumulativeTimePerToken;
        int256  stCumulativePnlPerToken;
        // lp/td states
        int256  preStAmount;
        int256  cumulativeTime;
        int256  cumulativePnl;
        int256  cumulativeTimePerToken;
        int256  cumulativePnlPerToken;
        int256  lastCumulativePnl;
        int256  cumulativeProtocolFee;
    }

    function _checkRequestId(mapping(uint8 => bytes32) storage state, uint8 index, uint256 requestId) internal {
        uint256 lastRequestId = state.getUint(index);
        if (requestId > lastRequestId) {
            state.set(index, requestId);
        } else {
            revert InvalidRequestId();
        }
    }

    function _checkStTokenId(mapping(uint8 => bytes32) storage state, uint8 index, bytes32 stTokenId) internal {
        bytes32 lastStTokenId = state.getBytes32(index);
        if (lastStTokenId == bytes32(0)) {
            state.set(index, stTokenId);
        } else if (lastStTokenId != stTokenId) {
            revert InvalidStTokenId();
        }
    }

    function _getData(uint8 action, uint256 requestId, uint256 userTokenId, bytes32 stTokenId)
    internal returns (Data memory data)
    {
        if (action == ACTION_ADDLIQUIDITY || action == ACTION_REMOVELIQUIDITY) {
            _checkRequestId(_lpStates[userTokenId], SLP_LASTREQUESTID, requestId);
            _checkStTokenId(_lpStates[userTokenId], SLP_STTOKENID, stTokenId);
        } else if (action != ACTION_POSTLIQUIDATE) {
            _checkRequestId(_tdStates[userTokenId], STD_LASTREQUESTID, requestId);
            _checkStTokenId(_tdStates[userTokenId], STD_STTOKENID, stTokenId);
        } else {
            _checkRequestId(_tdStates[userTokenId], STD_LASTREQUESTID, requestId);
        }

        data.liquidity = _states.getInt(S_LIQUIDITY);
        data.lpsPnl = _states.getInt(S_LPSPNL);
        data.cumulativePnlPerLiquidity = _states.getInt(S_CUMULATIVEPNLPERLIQUIDITY);

        data.cumulativePnl = _lpStates[userTokenId].getInt(SLP_CUMULATIVEPNL);

        if (action == ACTION_ADDLIQUIDITY || action == ACTION_REMOVELIQUIDITY) {
            data.cumulativeTimePerLiquidity = _states.getInt(S_CUMULATIVETIMEPERLIQUIDITY);
            data.lastTimestamp = _states.getInt(S_LASTTIMESTAMP);

            data.preStPrice = _stTokenStates[stTokenId].getInt(ST_PRICE);
            data.preStTotalAmount = _stTokenStates[stTokenId].getInt(ST_TOTALAMOUNT);
            data.stCumulativeTimePerLiquidity = _stTokenStates[stTokenId].getInt(ST_CUMULATIVETIMEPERLIQUIDITY);
            data.stCumulativePnlPerLiquidity = _stTokenStates[stTokenId].getInt(ST_CUMULATIVEPNLPERLIQUIDITY);
            data.stCumulativeTimePerToken = _stTokenStates[stTokenId].getInt(ST_CUMULATIVETIMEPERTOKEN);
            data.stCumulativePnlPerToken = _stTokenStates[stTokenId].getInt(ST_CUMULATIVEPNLPERTOKEN);

            data.preStAmount = _lpStates[userTokenId].getInt(SLP_STAMOUNT);
            data.cumulativeTime = _lpStates[userTokenId].getInt(SLP_CUMULATIVETIME);
            data.cumulativeTimePerToken = _lpStates[userTokenId].getInt(SLP_CUMULATIVETIMEPERTOKEN);
            data.cumulativePnlPerToken = _lpStates[userTokenId].getInt(SLP_CUMULATIVEPNLPERTOKEN);

            if (action == ACTION_REMOVELIQUIDITY) {
                data.lastCumulativePnl = _lpStates[userTokenId].getInt(SLP_LASTCUMULATIVEPNL);
            }
        } else if (action != ACTION_POSTLIQUIDATE) {
            data.cumulativeProtocolFee = _tdStates[userTokenId].getInt(STD_CUMULATIVEPROTOCOLFEE);
        }
    }

    function _settleStTokenTime(Data memory data) view internal {
        int256 diffCumulativeTimePerLiquidity;

        if (data.liquidity > 0) {
            diffCumulativeTimePerLiquidity = (int256(block.timestamp) - data.lastTimestamp) * ONE * ONE / data.liquidity;
            unchecked {
                data.cumulativeTimePerLiquidity += diffCumulativeTimePerLiquidity;
            }
        }
        data.lastTimestamp = int256(block.timestamp);

        if (data.preStTotalAmount > 0) {
            unchecked {
                diffCumulativeTimePerLiquidity = data.cumulativeTimePerLiquidity - data.stCumulativeTimePerLiquidity;
            }
            int256 diffCumulativeTimePerToken = diffCumulativeTimePerLiquidity * data.preStPrice / ONE;
            unchecked {
                data.stCumulativeTimePerToken += diffCumulativeTimePerToken;
            }
        }
        data.stCumulativeTimePerLiquidity = data.cumulativeTimePerLiquidity;
    }

    function _settleStTokenPnl(Data memory data) pure internal {
        if (data.preStTotalAmount > 0) {
            int256 diffCumulativePnlPerLiquidity;
            unchecked {
                diffCumulativePnlPerLiquidity = data.cumulativePnlPerLiquidity - data.stCumulativePnlPerLiquidity;
            }
            int256 diffCumulativePnlPerToken = diffCumulativePnlPerLiquidity * data.preStPrice / ONE;
            unchecked {
                data.stCumulativePnlPerToken += diffCumulativePnlPerToken;
            }
        }
        data.stCumulativePnlPerLiquidity = data.cumulativePnlPerLiquidity;
    }

    function _settleLp(Data memory data) pure internal {
        if (data.preStAmount > 0) {
            int256 diffCumulativeTimePerToken;
            unchecked {
                diffCumulativeTimePerToken = data.stCumulativeTimePerToken - data.cumulativeTimePerToken;
            }
            data.cumulativeTime += diffCumulativeTimePerToken * data.preStAmount / ONE;

            int256 diffCumulativePnlPerToken;
            unchecked {
                diffCumulativePnlPerToken = data.stCumulativePnlPerToken - data.cumulativePnlPerToken;
            }
            data.cumulativePnl += diffCumulativePnlPerToken * data.preStAmount / ONE;
        }
        data.cumulativeTimePerToken = data.stCumulativeTimePerToken;
        data.cumulativePnlPerToken = data.stCumulativePnlPerToken;
    }

    function _onlySelf() internal view {
        if (msg.sender != address(this)) {
            revert OnlySelf();
        }
    }

    function _updateOracle(IOracle.Signature[] memory signatures) internal {
        IOracle oracle = IOracle(_states.getAddress(S_ORACLE));
        for (uint256 i = 0; i < signatures.length; i++) {
            oracle.updateOffchainValue(signatures[i]);
        }
    }

    //================================================================================
    // Actions
    //================================================================================

    function _addLiquidity(IPool.VarOnAddLiquidity memory v, IOracle.Signature[] memory signatures) external {
        _onlySelf();
        _updateOracle(signatures);

        int256 curStPrice = v.stPrice.utoi();
        int256 curStAmount = v.stAmount.utoi();
        Data memory data = _getData(ACTION_ADDLIQUIDITY, v.requestId, v.lTokenId, v.stTokenId);

        if (data.liquidity > 0) {
            ISymbolManager.SettlementOnAddLiquidity memory s =
            ISymbolManager(_states.getAddress(S_SYMBOLMANAGER)).settleSymbolsOnAddLiquidity(data.liquidity + data.lpsPnl);

            int256 undistributedPnl = s.funding - s.diffTradersPnl;
            data.lpsPnl += undistributedPnl;
            int256 diffCumulativePnlPerLiquidity = undistributedPnl * ONE / data.liquidity;
            unchecked {
                data.cumulativePnlPerLiquidity += diffCumulativePnlPerLiquidity;
            }
        }

        _settleStTokenTime(data);
        _settleStTokenPnl(data);
        _settleLp(data);

        int256 curStTotalAmount = data.preStTotalAmount + curStAmount - data.preStAmount;
        data.liquidity += (curStTotalAmount * curStPrice - data.preStTotalAmount * data.preStPrice) / ONE;

        _states.set(S_LIQUIDITY, data.liquidity);
        _states.set(S_LPSPNL, data.lpsPnl);
        _states.set(S_CUMULATIVETIMEPERLIQUIDITY, data.cumulativeTimePerLiquidity);
        _states.set(S_CUMULATIVEPNLPERLIQUIDITY, data.cumulativePnlPerLiquidity);
        _states.set(S_LASTTIMESTAMP, data.lastTimestamp);

        _stTokenStates[v.stTokenId].set(ST_PRICE, curStPrice);
        _stTokenStates[v.stTokenId].set(ST_TOTALAMOUNT, curStTotalAmount);
        _stTokenStates[v.stTokenId].set(ST_CUMULATIVETIMEPERLIQUIDITY, data.stCumulativeTimePerLiquidity);
        _stTokenStates[v.stTokenId].set(ST_CUMULATIVEPNLPERLIQUIDITY, data.stCumulativePnlPerLiquidity);
        _stTokenStates[v.stTokenId].set(ST_CUMULATIVETIMEPERTOKEN, data.stCumulativeTimePerToken);
        _stTokenStates[v.stTokenId].set(ST_CUMULATIVEPNLPERTOKEN, data.stCumulativePnlPerToken);

        _lpStates[v.lTokenId].set(SLP_STAMOUNT, curStAmount);
        _lpStates[v.lTokenId].set(SLP_CUMULATIVETIME, data.cumulativeTime);
        _lpStates[v.lTokenId].set(SLP_CUMULATIVEPNL, data.cumulativePnl);
        _lpStates[v.lTokenId].set(SLP_CUMULATIVETIMEPERTOKEN, data.cumulativeTimePerToken);
        _lpStates[v.lTokenId].set(SLP_CUMULATIVEPNLPERTOKEN, data.cumulativePnlPerToken);

        emit AddLiquidity(
            v.requestId,
            v.lTokenId,
            v.stTokenId,
            v.stPrice,
            v.stAmount
        );
    }

    function _removeLiquidity(IPool.VarOnRemoveLiquidity memory v, IOracle.Signature[] memory signatures) external {
        _onlySelf();
        _updateOracle(signatures);

        int256 curStPrice = v.stPrice.utoi();
        int256 curStAmount = v.stAmount.utoi();
        Data memory data = _getData(ACTION_REMOVELIQUIDITY, v.requestId, v.lTokenId, v.stTokenId);

        int256 removedLiquidity = (data.preStAmount - curStAmount) * data.preStPrice / ONE;
        ISymbolManager.SettlementOnRemoveLiquidity memory s =
        ISymbolManager(_states.getAddress(S_SYMBOLMANAGER)).settleSymbolsOnRemoveLiquidity(data.liquidity + data.lpsPnl, removedLiquidity);

        int256 undistributedPnl = s.funding - s.diffTradersPnl + s.removeLiquidityPenalty;
        data.lpsPnl += undistributedPnl;
        int256 diffCumulativePnlPerLiquidity = undistributedPnl * ONE / data.liquidity;
        unchecked {
            data.cumulativePnlPerLiquidity += diffCumulativePnlPerLiquidity;
        }
        data.cumulativePnl -= s.removeLiquidityPenalty;

        _settleStTokenTime(data);
        _settleStTokenPnl(data);
        _settleLp(data);

        int256 curStTotalAmount = data.preStTotalAmount + curStAmount - data.preStAmount;
        data.liquidity += (curStTotalAmount * curStPrice - data.preStTotalAmount * data.preStPrice) / ONE;
        data.lpsPnl -= data.cumulativePnl - data.lastCumulativePnl;
        data.lastCumulativePnl = data.cumulativePnl;

        if ((data.liquidity + data.lpsPnl) * ONE < s.initialMarginRequired * _states.getInt(S_INITIALMARGINMULTIPLIER)) {
            revert InsufficientLiquidity();
        }

        _states.set(S_LIQUIDITY, data.liquidity);
        _states.set(S_LPSPNL, data.lpsPnl);
        _states.set(S_CUMULATIVETIMEPERLIQUIDITY, data.cumulativeTimePerLiquidity);
        _states.set(S_CUMULATIVEPNLPERLIQUIDITY, data.cumulativePnlPerLiquidity);
        _states.set(S_LASTTIMESTAMP, data.lastTimestamp);

        _stTokenStates[v.stTokenId].set(ST_PRICE, curStPrice);
        _stTokenStates[v.stTokenId].set(ST_TOTALAMOUNT, curStTotalAmount);
        _stTokenStates[v.stTokenId].set(ST_CUMULATIVETIMEPERLIQUIDITY, data.stCumulativeTimePerLiquidity);
        _stTokenStates[v.stTokenId].set(ST_CUMULATIVEPNLPERLIQUIDITY, data.stCumulativePnlPerLiquidity);
        _stTokenStates[v.stTokenId].set(ST_CUMULATIVETIMEPERTOKEN, data.stCumulativeTimePerToken);
        _stTokenStates[v.stTokenId].set(ST_CUMULATIVEPNLPERTOKEN, data.stCumulativePnlPerToken);

        _lpStates[v.lTokenId].set(SLP_STAMOUNT, curStAmount);
        _lpStates[v.lTokenId].set(SLP_CUMULATIVETIME, data.cumulativeTime);
        _lpStates[v.lTokenId].set(SLP_CUMULATIVEPNL, data.cumulativePnl);
        _lpStates[v.lTokenId].set(SLP_CUMULATIVETIMEPERTOKEN, data.cumulativeTimePerToken);
        _lpStates[v.lTokenId].set(SLP_CUMULATIVEPNLPERTOKEN, data.cumulativePnlPerToken);
        _lpStates[v.lTokenId].set(SLP_LASTCUMULATIVEPNL, data.lastCumulativePnl);

        if (curStAmount == 0) {
            _lpStates[v.lTokenId].set(SLP_STTOKENID, bytes32(0));
        }

        emit RemoveLiquidity(
            v.requestId,
            v.lTokenId,
            v.stTokenId,
            v.stPrice,
            v.stAmount,
            data.cumulativePnl
        );
    }

    function _removeMargin(IPool.VarOnRemoveMargin memory v, IOracle.Signature[] memory signatures) external {
        _onlySelf();
        _updateOracle(signatures);

        int256 curStPrice = v.stPrice.utoi();
        int256 curStAmount = v.stAmount.utoi();
        Data memory data = _getData(ACTION_TRADERWITHPOSTION, v.requestId, v.pTokenId, v.stTokenId);

        ISymbolManager.SettlementOnRemoveMargin memory s =
        ISymbolManager(_states.getAddress(S_SYMBOLMANAGER)).settleSymbolsOnRemoveMargin(v.pTokenId, data.liquidity + data.lpsPnl);

        int256 undistributedPnl = s.funding - s.diffTradersPnl;
        data.lpsPnl += undistributedPnl;
        int256 diffCumulativePnlPerLiquidity = undistributedPnl * ONE / data.liquidity;
        unchecked {
            data.cumulativePnlPerLiquidity += diffCumulativePnlPerLiquidity;
        }

        data.cumulativePnl -= s.traderFunding;

        int256 requiredMargin = s.traderInitialMarginRequired - s.traderPnl;
        if (curStAmount * curStPrice / ONE + (data.cumulativePnl - v.lastCumulativePnl) < requiredMargin) {
            revert InsufficientMargin();
        }

        _states.set(S_LPSPNL, data.lpsPnl);
        _states.set(S_CUMULATIVETIMEPERLIQUIDITY, data.cumulativeTimePerLiquidity);

        _tdStates[v.pTokenId].set(STD_CUMULATIVEPNL, data.cumulativePnl);

        if (curStAmount == 0) {
            _tdStates[v.pTokenId].set(STD_STTOKENID, bytes32(0));
        }

        emit RemoveMargin(
            v.requestId,
            v.pTokenId,
            v.stTokenId,
            v.stPrice,
            v.stAmount,
            data.cumulativePnl,
            data.cumulativeProtocolFee,
            requiredMargin
        );
    }

    function _trade(IPool.VarOnTrade memory v, IOracle.Signature[] memory signatures) external {
        _onlySelf();
        _updateOracle(signatures);

        int256 curStPrice = v.stPrice.utoi();
        int256 curStAmount = v.stAmount.utoi();
        Data memory data = _getData(ACTION_TRADE, v.requestId, v.pTokenId, v.stTokenId);

        ISymbolManager.SettlementOnTrade memory s =
        ISymbolManager(_states.getAddress(S_SYMBOLMANAGER)).settleSymbolsOnTrade(
            v.symbolId,
            v.pTokenId,
            data.liquidity + data.lpsPnl,
            v.tradeParams
        );

        int256 collect = s.tradeFee * _states.getInt(S_PROTOCOLFEECOLLECTIONRATIO) / ONE;
        data.cumulativeProtocolFee += collect;

        int256 undistributedPnl = s.funding - s.diffTradersPnl + s.tradeFee - collect + s.tradeRealizedCost;
        data.lpsPnl += undistributedPnl;
        int256 diffCumulativePnlPerLiquidity = undistributedPnl * ONE / data.liquidity;
        unchecked {
            data.cumulativePnlPerLiquidity += diffCumulativePnlPerLiquidity;
        }

        data.cumulativePnl -= s.traderFunding + s.tradeFee + s.tradeRealizedCost;

        if ((data.liquidity + data.lpsPnl) * ONE < s.initialMarginRequired * _states.getInt(S_INITIALMARGINMULTIPLIER)) {
            revert InsufficientLiquidity();
        }

        int256 requiredMargin = s.traderInitialMarginRequired - s.traderPnl;
        if (curStAmount * curStPrice / ONE + (data.cumulativePnl - v.lastCumulativePnl) < requiredMargin) {
            revert InsufficientMargin();
        }

        _states.set(S_LPSPNL, data.lpsPnl);
        _states.set(S_CUMULATIVETIMEPERLIQUIDITY, data.cumulativeTimePerLiquidity);

        _tdStates[v.pTokenId].set(STD_CUMULATIVEPNL, data.cumulativePnl);
        _tdStates[v.pTokenId].set(STD_CUMULATIVEPROTOCOLFEE, data.cumulativeProtocolFee);

        if (curStAmount == 0) {
            _tdStates[v.pTokenId].set(STD_STTOKENID, bytes32(0));
        }

        emit Trade(
            v.requestId,
            v.pTokenId,
            v.stTokenId,
            v.stPrice,
            v.stAmount,
            data.cumulativePnl,
            data.cumulativeProtocolFee,
            requiredMargin
        );
    }

    function _liquidate(IPool.VarOnLiquidate memory v, IOracle.Signature[] memory signatures) external {
        _onlySelf();
        _updateOracle(signatures);

        int256 curStPrice = v.stPrice.utoi();
        int256 curStAmount = v.stAmount.utoi();
        Data memory data = _getData(ACTION_LIQUIDATE, v.requestId, v.pTokenId, v.stTokenId);

        ISymbolManager.SettlementOnLiquidate memory s =
        ISymbolManager(_states.getAddress(S_SYMBOLMANAGER)).settleSymbolsOnLiquidate(v.pTokenId, data.liquidity + data.lpsPnl);

        int256 undistributedPnl = s.funding - s.diffTradersPnl + s.tradeRealizedCost;
        data.lpsPnl += undistributedPnl;
        int256 diffCumulativePnlPerLiquidity = undistributedPnl * ONE / data.liquidity;
        unchecked {
            data.cumulativePnlPerLiquidity += diffCumulativePnlPerLiquidity;
        }

        data.cumulativePnl -= s.traderFunding;

        if (s.traderMaintenanceMarginRequired <= 0) {
            revert NoMaintenanceMarginRequired();
        }

        int256 availableMargin = curStAmount * curStPrice / ONE + (data.cumulativePnl - v.lastCumulativePnl);

        if (availableMargin + s.traderPnl > s.traderMaintenanceMarginRequired) {
            revert CanNotLiquidate();
        }

        data.cumulativePnl -= s.tradeRealizedCost;

        _states.set(S_LPSPNL, data.lpsPnl);
        _states.set(S_CUMULATIVETIMEPERLIQUIDITY, data.cumulativeTimePerLiquidity);

        _tdStates[v.pTokenId].set(STD_CUMULATIVEPNL, data.cumulativePnl);
        _tdStates[v.pTokenId].set(STD_STTOKENID, bytes32(0));

        emit Liquidate(
            v.requestId,
            v.pTokenId,
            v.stTokenId,
            v.stPrice,
            v.stAmount,
            data.cumulativePnl,
            data.cumulativeProtocolFee
        );
    }

    function _postLiquidate(IPool.VarOnPostLiquidate memory v) external {
        _onlySelf();

        Data memory data = _getData(ACTION_POSTLIQUIDATE, v.requestId, v.pTokenId, bytes32(0));

        int256 undistributedPnl = v.lastCumulativePnl - data.cumulativePnl;
        data.lpsPnl += undistributedPnl;
        int256 diffCumulativePnlPerLiquidity = undistributedPnl * ONE / data.liquidity;
        unchecked {
            data.cumulativePnlPerLiquidity += diffCumulativePnlPerLiquidity;
        }

        data.cumulativePnl = v.lastCumulativePnl;

        _states.set(S_LPSPNL, data.lpsPnl);
        _states.set(S_CUMULATIVETIMEPERLIQUIDITY, data.cumulativeTimePerLiquidity);

        _tdStates[v.pTokenId].set(STD_CUMULATIVEPNL, data.cumulativePnl);

        emit PostLiquidate(
            v.requestId,
            v.pTokenId,
            data.cumulativePnl
        );
    }

}
