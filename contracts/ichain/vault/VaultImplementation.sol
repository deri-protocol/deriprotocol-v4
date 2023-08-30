// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './IVault.sol';
import '../token/IDToken.sol';
import '../token/IIOU.sol';
import '../../oracle/IOracle.sol';
import '../swapper/ISwapper.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '../../library/Bytes32Map.sol';
import '../../library/ETHAndERC20.sol';
import '../../library/SafeMath.sol';
import '../venus/VenusBnb.sol';
import '../aave/AaveArbitrum.sol';
import './VaultStorage.sol';

contract VaultImplementation is VaultStorage {

    using Bytes32Map for mapping(uint8 => bytes32);
    using ETHAndERC20 for address;
    using SafeMath for uint256;
    using SafeMath for int256;

    error CannotDelBToken();
    error BTokenDupInitialize();
    error BTokenNoSwapper();
    error BTokenNoOracle();
    error InvalidBToken();
    error InvalidBPrice();
    error InvalidCustodian();
    error InvalidLTokenId();
    error InvalidPTokenId();
    error InvalidRequestId();
    error InsufficientMargin();
    error InvalidSignature();

    event AddBToken(address bToken, uint256 custodian, bytes32 oracleId, uint256 collateralFactor);

    event DelBToken(address bToken);

    event UpdateBToken(address bToken);

    event RequestAddLiquidity(
        uint256 requestId,
        uint256 lTokenId,
        uint256 liquidity,
        int256  lastCumulativePnlOnEngine,
        int256  cumulativePnlOnVault
    );

    event RequestRemoveLiquidity(
        uint256 requestId,
        uint256 lTokenId,
        uint256 liquidity,
        int256  lastCumulativePnlOnEngine,
        int256  cumulativePnlOnVault,
        uint256 bAmount
    );

    event RequestRemoveMargin(
        uint256 requestId,
        uint256 pTokenId,
        uint256 margin,
        int256  lastCumulativePnlOnEngine,
        int256  cumulativePnlOnVault,
        uint256 bAmount
    );

    event RequestTrade(
        uint256 requestId,
        uint256 pTokenId,
        uint256 margin,
        int256  lastCumulativePnlOnEngine,
        int256  cumulativePnlOnVault,
        bytes32 symbolId,
        int256[] tradeParams
    );

    event RequestLiquidate(
        uint256 requestId,
        uint256 pTokenId,
        uint256 margin,
        int256  lastCumulativePnlOnEngine,
        int256  cumulativePnlOnVault
    );

    event RequestTradeAndRemoveMargin(
        uint256 requestId,
        uint256 pTokenId,
        uint256 margin,
        int256  lastCumulativePnlOnEngine,
        int256  cumulativePnlOnVault,
        uint256 bAmount,
        bytes32 symbolId,
        int256[] tradeParams
    );

    event AddLiquidity(
        uint256 requestId,
        uint256 lTokenId,
        uint256 liquidity,
        uint256 totalLiquidity
    );

    event RemoveLiquidity(
        uint256 requestId,
        uint256 lTokenId,
        uint256 liquidity,
        uint256 totalLiquidity,
        address bToken,
        uint256 bAmount
    );

    event AddMargin(
        uint256 requestId,
        uint256 pTokenId,
        address bToken,
        uint256 bAmount
    );

    event RemoveMargin(
        uint256 requestId,
        uint256 pTokenId,
        address bToken,
        uint256 bAmount
    );

    event Liquidate(
        uint256 requestId,
        uint256 pTokenId,
        int256  lpPnl
    );

    uint8 constant S_ST0AMOUNT                  = 1;
    uint8 constant S_CUMULATIVEPNLONVAULT       = 2;
    uint8 constant S_LIQUIDITYTIME              = 3;
    uint8 constant S_TOTALLIQUIDITY             = 4;
    uint8 constant S_CUMULATIVETIMEPERLIQUIDITY = 5;

    uint8 constant B_INITIALIZED       = 1;
    uint8 constant B_CUSTODIAN         = 2;
    uint8 constant B_ORACLEID          = 3;
    uint8 constant B_COLLECTERALFACTOR = 4;
    uint8 constant B_STTOTALAMOUNT     = 5;

    uint8 constant D_REQUESTID                      = 1;
    uint8 constant D_BTOKEN                         = 2;
    uint8 constant D_STAMOUNT                       = 3;
    uint8 constant D_B0AMOUNT                       = 4;
    uint8 constant D_LASTCUMULATIVEPNLONENGINE      = 5;
    uint8 constant D_LIQUIDITY                      = 6;
    uint8 constant D_CUMULATIVETIME                 = 7;
    uint8 constant D_LASTCUMULATIVETIMEPERLIQUIDITY = 8;

    uint256 constant CUSTODIAN_NONE         = 1;
    uint256 constant CUSTODIAN_VENUSBNB     = 2;
    uint256 constant CUSTODIAN_AAVEARBITRUM = 3;

    uint256 constant UONE = 1e18;
    int256  constant ONE = 1e18;
    address constant tokenETH = address(1);

    IDToken  internal immutable lToken;
    IDToken  internal immutable pToken;
    IOracle  internal immutable oracle;
    ISwapper internal immutable swapper;
    IIOU     internal immutable iou;
    address  internal immutable tokenB0;
    uint8    internal immutable decimalsB0;
    address  internal immutable eventSigner;
    uint256  internal immutable b0ReserveRatio;
    int256   internal immutable liquidationRewardCutRatio;
    int256   internal immutable minLiquidationReward;
    int256   internal immutable maxLiquidationReward;

    constructor (
        address lToken_,
        address pToken_,
        address oracle_,
        address swapper_,
        address iou_,
        address tokenB0_,
        address eventSigner_,
        uint256 b0ReserveRatio_,
        int256  liquidationRewardCutRatio_,
        int256  minLiquidationReward_,
        int256  maxLiquidationReward_
    ) {
        lToken = IDToken(lToken_);
        pToken = IDToken(pToken_);
        oracle = IOracle(oracle_);
        swapper = ISwapper(swapper_);
        iou = IIOU(iou_);
        tokenB0 = tokenB0_;
        decimalsB0 = tokenB0_.decimals();
        eventSigner = eventSigner_;
        b0ReserveRatio = b0ReserveRatio_;
        liquidationRewardCutRatio = liquidationRewardCutRatio_;
        minLiquidationReward = minLiquidationReward_;
        maxLiquidationReward = maxLiquidationReward_;
    }

    //================================================================================
    // Getters
    //================================================================================

    function getVaultParam() external view returns (IVault.VaultParam memory p) {
        p.lToken = address(lToken);
        p.pToken = address(pToken);
        p.oracle = address(oracle);
        p.swapper = address(swapper);
        p.iou = address(iou);
        p.tokenB0 = tokenB0;
        p.eventSigner = eventSigner;
        p.b0ReserveRatio = b0ReserveRatio;
        p.liquidationRewardCutRatio = liquidationRewardCutRatio;
        p.minLiquidationReward = minLiquidationReward;
        p.maxLiquidationReward = maxLiquidationReward;
    }

    function getVaultState() external view returns (IVault.VaultState memory s) {
        s.st0Amount = _vaultStates.getUint(S_ST0AMOUNT);
        s.cumulativePnlOnVault = _vaultStates.getInt(S_CUMULATIVEPNLONVAULT);
        s.liquidityTime = _vaultStates.getUint(S_LIQUIDITYTIME);
        s.totalLiquidity = _vaultStates.getUint(S_TOTALLIQUIDITY);
        s.cumulativeTimePerLiquidity = _vaultStates.getInt(S_CUMULATIVETIMEPERLIQUIDITY);
    }

    function getBTokenState(address bToken) external view returns (IVault.BTokenState memory s) {
        s.bToken = bToken;
        s.initialized = _bTokenStates[bToken].getBool(B_INITIALIZED);
        s.custodian = _bTokenStates[bToken].getUint(B_CUSTODIAN);
        s.oracleId = _bTokenStates[bToken].getBytes32(B_ORACLEID);
        s.collateralFactor = _bTokenStates[bToken].getUint(B_COLLECTERALFACTOR);
        s.stTotalAmount = _bTokenStates[bToken].getUint(B_STTOTALAMOUNT);
    }

    function getLpState(uint256 lTokenId) external view returns (IVault.LpState memory s) {
        s.requestId = _dTokenStates[lTokenId].getUint(D_REQUESTID);
        s.bToken = _dTokenStates[lTokenId].getAddress(D_BTOKEN);
        s.stAmount = _dTokenStates[lTokenId].getUint(D_STAMOUNT);
        s.b0Amount = _dTokenStates[lTokenId].getInt(D_B0AMOUNT);
        s.lastCumulativePnlOnEngine = _dTokenStates[lTokenId].getInt(D_LASTCUMULATIVEPNLONENGINE);
        s.liquidity = _dTokenStates[lTokenId].getUint(D_LIQUIDITY);
        s.cumulativeTime = _dTokenStates[lTokenId].getUint(D_CUMULATIVETIME);
        s.lastCumulativeTimePerLiquidity = _dTokenStates[lTokenId].getUint(D_LASTCUMULATIVETIMEPERLIQUIDITY);
    }

    function getTdState(uint256 pTokenId) external view returns (IVault.TdState memory s) {
        s.requestId = _dTokenStates[pTokenId].getUint(D_REQUESTID);
        s.bToken = _dTokenStates[pTokenId].getAddress(D_BTOKEN);
        s.stAmount = _dTokenStates[pTokenId].getUint(D_STAMOUNT);
        s.b0Amount = _dTokenStates[pTokenId].getInt(D_B0AMOUNT);
        s.lastCumulativePnlOnEngine = _dTokenStates[pTokenId].getInt(D_LASTCUMULATIVEPNLONENGINE);
    }

    function getCumulativeTime(uint256 lTokenId)
    public view returns (uint256 cumulativeTimePerLiquidity, uint256 cumulativeTime)
    {
        uint256 liquidityTime = _vaultStates.getUint(S_LIQUIDITYTIME);
        uint256 totalLiquidity = _vaultStates.getUint(S_TOTALLIQUIDITY);
        cumulativeTimePerLiquidity = _vaultStates.getUint(S_CUMULATIVETIMEPERLIQUIDITY);
        uint256 liquidity = _dTokenStates[lTokenId].getUint(D_LIQUIDITY);
        cumulativeTime = _dTokenStates[lTokenId].getUint(D_CUMULATIVETIME);
        uint256 lastCumulativeTimePerLiquidity = _dTokenStates[lTokenId].getUint(D_LASTCUMULATIVETIMEPERLIQUIDITY);

        if (totalLiquidity != 0) {
            uint256 diff1 = (block.timestamp - liquidityTime) * UONE * UONE / totalLiquidity;
            unchecked { cumulativeTimePerLiquidity += diff1; }

            if (liquidity != 0) {
                uint256 diff2;
                unchecked { diff2 = cumulativeTimePerLiquidity - lastCumulativeTimePerLiquidity; }
                cumulativeTime += diff2 * liquidity / UONE;
            }
        }
    }

    //================================================================================
    // Setters
    //================================================================================

    function addBToken(
        address bToken,
        uint256 custodian,
        bytes32 oracleId,
        uint256 collateralFactor
    ) external _onlyAdmin_ {
        if (_bTokenStates[bToken].getBool(B_INITIALIZED)) {
            revert BTokenDupInitialize();
        }
        if (bToken != tokenETH) {
            if (!swapper.isSupportedToken(bToken)) {
                revert BTokenNoSwapper();
            }
            bToken.approveMax(address(swapper));
        }
        if (oracle.getValue(oracleId) == 0) {
            revert BTokenNoOracle();
        }
        _bTokenStates[bToken].set(B_INITIALIZED, true);
        _bTokenStates[bToken].set(B_CUSTODIAN, custodian);
        _bTokenStates[bToken].set(B_ORACLEID, oracleId);
        _bTokenStates[bToken].set(B_COLLECTERALFACTOR, collateralFactor);

        if (custodian == CUSTODIAN_VENUSBNB) {
            VenusBnb.enterMarket(bToken);
        } else if (custodian == CUSTODIAN_AAVEARBITRUM) {
            AaveArbitrum.enterMarket(bToken);
        }

        emit AddBToken(bToken, custodian, oracleId, collateralFactor);
    }

    function delBToken(address bToken) external _onlyAdmin_ {
        if (_bTokenStates[bToken].getUint(B_STTOTALAMOUNT) != 0) {
            revert CannotDelBToken();
        }
        _bTokenStates[bToken].set(B_INITIALIZED, false);

        uint256 custodian = _bTokenStates[bToken].getUint(B_CUSTODIAN);
        if (custodian == CUSTODIAN_VENUSBNB) {
            VenusBnb.exitMarket(bToken);
        } else if (custodian == CUSTODIAN_AAVEARBITRUM) {
            AaveArbitrum.exitMarket(bToken);
        }

        emit DelBToken(bToken);
    }

    function setBTokenParameter(address bToken, uint8 idx, bytes32 value) external _onlyAdmin_ {
        _bTokenStates[bToken].set(idx, value);
        emit UpdateBToken(bToken);
    }

    //================================================================================
    // Interactions
    //================================================================================

    function redeemIOU(uint256 b0Amount) external {
        if (b0Amount > 0) {
            Data memory data;
            data.st0Amount = _vaultStates.getUint(S_ST0AMOUNT);
            data.st0TotalAmount = _bTokenStates[tokenB0].getUint(B_STTOTALAMOUNT);
            uint256 b0Redeemed = _redeemReserveB0(data, b0Amount);
            if (b0Redeemed > 0) {
                tokenB0.transferOut(msg.sender, b0Redeemed);
                iou.burn(msg.sender, b0Redeemed);
            }
            _vaultStates.set(S_ST0AMOUNT, data.st0Amount);
            _bTokenStates[tokenB0].set(B_STTOTALAMOUNT, data.st0TotalAmount);
        }
    }

    function requestAddLiquidity(uint256 lTokenId, address bToken, uint256 bAmount) external payable {
        if (lTokenId == 0) {
            lTokenId = lToken.mint(msg.sender);
        } else {
            _checkLTokenIdOwner(lTokenId, msg.sender);
        }
        _checkBTokenInitialized(bToken);
        if (bToken == tokenETH) {
            bAmount = msg.value;
        }

        Data memory data = _getData(msg.sender, lTokenId, bToken);

        bToken.transferIn(data.account, bAmount);
        _deposit(data, bAmount);
        _getExParams(data);
        uint256 newLiquidity = _getDTokenLiquidity(data);

        _saveData(data);

        uint256 requestId = _incrementRequestId(lTokenId);
        emit RequestAddLiquidity(
            requestId,
            lTokenId,
            newLiquidity,
            data.lastCumulativePnlOnEngine,
            data.cumulativePnlOnVault
        );
    }

    function requestRemoveLiquidity(uint256 lTokenId, address bToken, uint256 bAmount) external {
        _checkLTokenIdOwner(lTokenId, msg.sender);

        Data memory data = _getData(msg.sender, lTokenId, bToken);
        _getExParams(data);
        uint256 oldLiquidity = _getDTokenLiquidity(data);
        uint256 newLiquidity = _getDTokenLiquidityWithRemove(data, bAmount);
        if (newLiquidity <= oldLiquidity / 20) {
            newLiquidity = 0;
        }

        uint256 requestId = _incrementRequestId(lTokenId);
        emit RequestRemoveLiquidity(
            requestId,
            lTokenId,
            newLiquidity,
            data.lastCumulativePnlOnEngine,
            data.cumulativePnlOnVault,
            bAmount
        );
    }

    function requestAddMargin(uint256 pTokenId, address bToken, uint256 bAmount) public payable returns (uint256) {
        if (pTokenId == 0) {
            pTokenId = pToken.mint(msg.sender);
        } else {
            _checkPTokenIdOwner(pTokenId, msg.sender);
        }
        _checkBTokenInitialized(bToken);
        if (bToken == tokenETH) {
            bAmount = msg.value;
        }

        Data memory data = _getData(msg.sender, pTokenId, bToken);
        bToken.transferIn(data.account, bAmount);
        _deposit(data, bAmount);

        _saveData(data);

        uint256 requestId = _incrementRequestId(pTokenId);
        emit AddMargin(
            requestId,
            pTokenId,
            bToken,
            bAmount
        );

        return pTokenId;
    }

    function requestRemoveMargin(uint256 pTokenId, address bToken, uint256 bAmount) external {
        _checkPTokenIdOwner(pTokenId, msg.sender);

        Data memory data = _getData(msg.sender, pTokenId, bToken);
        _getExParams(data);
        uint256 oldMargin = _getDTokenLiquidity(data);
        uint256 newMargin = _getDTokenLiquidityWithRemove(data, bAmount);
        if (newMargin <= oldMargin / 20) {
            newMargin = 0;
        }

        uint256 requestId = _incrementRequestId(pTokenId);
        emit RequestRemoveMargin(
            requestId,
            pTokenId,
            newMargin,
            data.lastCumulativePnlOnEngine,
            data.cumulativePnlOnVault,
            bAmount
        );
    }

    function requestTrade(uint256 pTokenId, bytes32 symbolId, int256[] calldata tradeParams) public {
        _checkPTokenIdOwner(pTokenId, msg.sender);

        Data memory data = _getData(msg.sender, pTokenId, _dTokenStates[pTokenId].getAddress(D_BTOKEN));
        _getExParams(data);
        uint256 margin = _getDTokenLiquidity(data);

        uint256 requestId = _incrementRequestId(pTokenId);
        emit RequestTrade(
            requestId,
            pTokenId,
            margin,
            data.lastCumulativePnlOnEngine,
            data.cumulativePnlOnVault,
            symbolId,
            tradeParams
        );
    }

    function requestLiquidate(uint256 pTokenId) external {
        Data memory data = _getData(pToken.ownerOf(pTokenId), pTokenId, _dTokenStates[pTokenId].getAddress(D_BTOKEN));
        _getExParams(data);
        uint256 margin = _getDTokenLiquidity(data);

        uint256 requestId = _incrementRequestId(pTokenId);
        emit RequestLiquidate(
            requestId,
            pTokenId,
            margin,
            data.lastCumulativePnlOnEngine,
            data.cumulativePnlOnVault
        );
    }

    function requestAddMarginAndTrade(
        uint256 pTokenId,
        address bToken,
        uint256 bAmount,
        bytes32 symbolId,
        int256[] calldata tradeParams
    ) external payable {
        pTokenId = requestAddMargin(pTokenId, bToken, bAmount);
        requestTrade(pTokenId, symbolId, tradeParams);
    }

    function requestTradeAndRemoveMargin(
        uint256 pTokenId,
        address bToken,
        uint256 bAmount,
        bytes32 symbolId,
        int256[] calldata tradeParams
    ) external {
        _checkPTokenIdOwner(pTokenId, msg.sender);

        Data memory data = _getData(msg.sender, pTokenId, bToken);
        _getExParams(data);
        uint256 oldMargin = _getDTokenLiquidity(data);
        uint256 newMargin = _getDTokenLiquidityWithRemove(data, bAmount);
        if (newMargin <= oldMargin / 20) {
            newMargin = 0;
        }

        uint256 requestId = _incrementRequestId(pTokenId);
        emit RequestTradeAndRemoveMargin(
            requestId,
            pTokenId,
            newMargin,
            data.lastCumulativePnlOnEngine,
            data.cumulativePnlOnVault,
            bAmount,
            symbolId,
            tradeParams
        );
    }

    function callbackAddLiquidity(bytes memory eventData, bytes memory signature) external {
        _verifyEventData(eventData, signature);
        IVault.VarOnCallbackAddLiquidity memory v = abi.decode(eventData, (IVault.VarOnCallbackAddLiquidity));
        _checkRequestId(v.lTokenId, v.requestId);

        _updateLiquidity(v.lTokenId, v.liquidity, v.totalLiquidity);

        int256 b0Amount = _dTokenStates[v.lTokenId].getInt(D_B0AMOUNT);
        int256 lastCumulativePnlOnEngine = _dTokenStates[v.lTokenId].getInt(D_LASTCUMULATIVEPNLONENGINE);
        int256 diff = v.cumulativePnlOnEngine.minusUnchecked(lastCumulativePnlOnEngine);
        b0Amount += diff.rescaleDown(18, decimalsB0);

        _dTokenStates[v.lTokenId].set(D_B0AMOUNT, b0Amount);
        _dTokenStates[v.lTokenId].set(D_LASTCUMULATIVEPNLONENGINE, v.cumulativePnlOnEngine);

        emit AddLiquidity(
            v.requestId,
            v.lTokenId,
            v.liquidity,
            v.totalLiquidity
        );
    }

    function callbackRemoveLiquidity(bytes memory eventData, bytes memory signature) external _reentryLock_ {
        _verifyEventData(eventData, signature);
        IVault.VarOnCallbackRemoveLiquidity memory v = abi.decode(eventData, (IVault.VarOnCallbackRemoveLiquidity));
        _checkRequestId(v.lTokenId, v.requestId);

        _updateLiquidity(v.lTokenId, v.liquidity, v.totalLiquidity);

        Data memory data = _getData(lToken.ownerOf(v.lTokenId), v.lTokenId, _dTokenStates[v.lTokenId].getAddress(D_BTOKEN));
        int256 diff = v.cumulativePnlOnEngine.minusUnchecked(data.lastCumulativePnlOnEngine);
        data.b0Amount += diff.rescaleDown(18, decimalsB0);
        data.lastCumulativePnlOnEngine = v.cumulativePnlOnEngine;

        _getExParams(data);
        uint256 bAmount = _transferOut(data, v.liquidity == 0 ? type(uint256).max : v.bAmount, false);

        _saveData(data);

        emit RemoveLiquidity(
            v.requestId,
            v.lTokenId,
            v.liquidity,
            v.totalLiquidity,
            data.bToken,
            bAmount
        );
    }

    function callbackRemoveMargin(bytes memory eventData, bytes memory signature) external _reentryLock_ {
        _verifyEventData(eventData, signature);
        IVault.VarOnCallbackRemoveMargin memory v = abi.decode(eventData, (IVault.VarOnCallbackRemoveMargin));
        _checkRequestId(v.pTokenId, v.requestId);

        Data memory data = _getData(pToken.ownerOf(v.pTokenId), v.pTokenId, _dTokenStates[v.pTokenId].getAddress(D_BTOKEN));
        int256 diff = v.cumulativePnlOnEngine.minusUnchecked(data.lastCumulativePnlOnEngine);
        data.b0Amount += diff.rescaleDown(18, decimalsB0);
        data.lastCumulativePnlOnEngine = v.cumulativePnlOnEngine;

        _getExParams(data);
        uint256 bAmount = _transferOut(data, v.bAmount, true);

        if (_getDTokenLiquidity(data) < v.requiredMargin) {
            revert InsufficientMargin();
        }

        _saveData(data);

        emit RemoveMargin(
            v.requestId,
            v.pTokenId,
            data.bToken,
            bAmount
        );
    }

    function callbackLiquidate(bytes memory eventData, bytes memory signature) external _reentryLock_ {
        _verifyEventData(eventData, signature);
        IVault.VarOnCallbackLiquidate memory v = abi.decode(eventData, (IVault.VarOnCallbackLiquidate));

        Data memory data = _getData(pToken.ownerOf(v.pTokenId), v.pTokenId, _dTokenStates[v.pTokenId].getAddress(D_BTOKEN));
        int256 diff = v.cumulativePnlOnEngine.minusUnchecked(data.lastCumulativePnlOnEngine);
        data.b0Amount += diff.rescaleDown(18, decimalsB0);
        data.lastCumulativePnlOnEngine = v.cumulativePnlOnEngine;

        uint256 b0AmountIn;
        if (data.stAmount > 0) {
            uint256 bAmount = _redeem(data.bToken, data.stAmount, data.stTotalAmount);
            if (data.bToken == tokenB0) {
                b0AmountIn += bAmount;
            } else if (data.bToken == tokenETH) {
                (uint256 resultB0, ) = swapper.swapExactETHForB0{value:bAmount}();
                b0AmountIn += resultB0;
            } else {
                (uint256 resultB0, ) = swapper.swapExactBXForB0(data.bToken, bAmount);
                b0AmountIn += resultB0;
            }
        }

        int256 lpPnl = b0AmountIn.utoi() + data.b0Amount;
        int256 reward;

        {
            if (lpPnl <= minLiquidationReward) {
                reward = minLiquidationReward;
            } else {
                reward = SafeMath.min(
                    (lpPnl - minLiquidationReward) * liquidationRewardCutRatio / ONE + minLiquidationReward,
                    maxLiquidationReward
                );
            }

            uint256 uReward = reward.itou();
            if (uReward <= b0AmountIn) {
                tokenB0.transferOut(msg.sender, uReward);
                b0AmountIn -= uReward;
            } else {
                uint256 b0Redeemed = _redeemReserveB0(data, uReward - b0AmountIn);
                tokenB0.transferOut(msg.sender, b0AmountIn + b0Redeemed);
                reward = (b0AmountIn + b0Redeemed).utoi();
                b0AmountIn = 0;
            }

            lpPnl -= reward;
        }

        if (b0AmountIn > 0) {
            _depositReserveB0(data, b0AmountIn);
        }

        data.cumulativePnlOnVault = data.cumulativePnlOnVault.addUnchecked(lpPnl.rescale(decimalsB0, 18));
        data.b0Amount = 0;
        _saveData(data);
        pToken.burn(v.pTokenId);

        emit Liquidate(
            v.requestId,
            v.pTokenId,
            lpPnl
        );
    }

    //================================================================================
    // Internals
    //================================================================================

    struct Data {
        address account;
        uint256 dTokenId;
        address bToken;

        uint256 st0Amount;
        int256  cumulativePnlOnVault;
        uint256 st0TotalAmount;
        uint256 stTotalAmount;

        uint256 stAmount;
        int256  b0Amount;
        int256  lastCumulativePnlOnEngine;

        uint256 collateralFactor;
        uint256 stExRate;
        uint256 bPrice;
    }

    function _getData(address account, uint256 dTokenId, address bToken) internal view returns (Data memory data) {
        data.account = account;
        data.dTokenId = dTokenId;
        data.bToken = bToken;

        data.st0Amount = _vaultStates.getUint(S_ST0AMOUNT);
        data.cumulativePnlOnVault = _vaultStates.getInt(S_CUMULATIVEPNLONVAULT);
        data.st0TotalAmount = _bTokenStates[tokenB0].getUint(B_STTOTALAMOUNT);
        data.stTotalAmount = _bTokenStates[bToken].getUint(B_STTOTALAMOUNT);

        data.stAmount = _dTokenStates[dTokenId].getUint(D_STAMOUNT);
        data.b0Amount = _dTokenStates[dTokenId].getInt(D_B0AMOUNT);
        data.lastCumulativePnlOnEngine = _dTokenStates[dTokenId].getInt(D_LASTCUMULATIVEPNLONENGINE);

        if (data.stAmount != 0) {
            _checkBTokenConsistency(dTokenId, bToken);
        }
    }

    function _saveData(Data memory data) internal {
        _vaultStates.set(S_ST0AMOUNT, data.st0Amount);
        _vaultStates.set(S_CUMULATIVEPNLONVAULT, data.cumulativePnlOnVault);
        _bTokenStates[tokenB0].set(B_STTOTALAMOUNT, data.st0TotalAmount);
        _bTokenStates[data.bToken].set(B_STTOTALAMOUNT, data.stTotalAmount);

        _dTokenStates[data.dTokenId].set(D_BTOKEN, data.bToken);
        _dTokenStates[data.dTokenId].set(D_STAMOUNT, data.stAmount);
        _dTokenStates[data.dTokenId].set(D_B0AMOUNT, data.b0Amount);
        _dTokenStates[data.dTokenId].set(D_LASTCUMULATIVEPNLONENGINE, data.lastCumulativePnlOnEngine);
    }

    function _checkRequestId(uint256 dTokenId, uint256 requestId) internal view {
        if (_dTokenStates[dTokenId].getUint(D_REQUESTID) != requestId) {
            revert InvalidRequestId();
        }
    }

    function _incrementRequestId(uint256 dTokenId) internal returns (uint256) {
        uint256 requestId = _dTokenStates[dTokenId].getUint(D_REQUESTID) + 1;
        _dTokenStates[dTokenId].set(D_REQUESTID, requestId);
        return requestId;
    }

    function _checkBTokenInitialized(address bToken) internal view {
        if (!_bTokenStates[bToken].getBool(B_INITIALIZED)) {
            revert InvalidBToken();
        }
    }

    function _checkBTokenConsistency(uint256 dTokenId, address bToken) internal view {
        if (bToken == address(0) || _dTokenStates[dTokenId].getAddress(D_BTOKEN) != bToken) {
            revert InvalidBToken();
        }
    }

    function _checkLTokenIdOwner(uint256 lTokenId, address owner) internal view {
        if (lToken.ownerOf(lTokenId) != owner) {
            revert InvalidLTokenId();
        }
    }

    function _checkPTokenIdOwner(uint256 pTokenId, address owner) internal view {
        if (pToken.ownerOf(pTokenId) != owner) {
            revert InvalidPTokenId();
        }
    }

    // stExRate * stAmount / UONE = bAmount, bAmount in decimalsB
    function _getStExRate(address bToken, uint256 stTotalAmount) internal view returns (uint256 stExRate) {
        uint256 custodian = _bTokenStates[bToken].getUint(B_CUSTODIAN);
        if (custodian == CUSTODIAN_NONE) {
            if (stTotalAmount != 0) {
                stExRate = bToken.balanceOfThis() * UONE / stTotalAmount;
            }
        }
        else if (custodian == CUSTODIAN_VENUSBNB) {
            stExRate = VenusBnb.getStExRate(bToken, stTotalAmount);
        }
        else if (custodian == CUSTODIAN_AAVEARBITRUM) {
            stExRate = AaveArbitrum.getStExRate(bToken, stTotalAmount);
        }
        else {
            revert InvalidCustodian();
        }
    }

    // bPrice * bAmount / UONE = b0Amount, b0Amount in decimalsB0
    function _getBPrice(address bToken) internal view returns (uint256 bPrice) {
        if (bToken == tokenB0) {
            bPrice = UONE;
        } else {
            uint8 decimalsB = bToken.decimals();
            bPrice = oracle.getValue(_bTokenStates[bToken].getBytes32(B_ORACLEID)).itou().rescale(decimalsB, decimalsB0);
            if (bPrice == 0) {
                revert InvalidBPrice();
            }
        }
    }

    function _getExParams(Data memory data) internal view {
        data.collateralFactor = _bTokenStates[data.bToken].getUint(B_COLLECTERALFACTOR);
        data.stExRate = _getStExRate(data.bToken, data.stTotalAmount);
        data.bPrice = _getBPrice(data.bToken);
    }

    // liquidity is in decimals18
    function _getDTokenLiquidity(Data memory data) internal view returns (uint256 liquidity) {
        uint256 b0Liquidity = (
            data.stAmount * data.stExRate / UONE * data.bPrice / UONE * data.collateralFactor / UONE
        ).add(data.b0Amount);
        return b0Liquidity.rescale(decimalsB0, 18);
    }

    function _getDTokenLiquidityWithRemove(Data memory data, uint256 bAmount) internal view returns (uint256 liquidity) {
        if (bAmount < type(uint256).max / data.bPrice) { // make sure bAmount * bPrice won't overflow
            uint256 bAmountInCustodian = data.stAmount * data.stExRate / UONE;
            if (bAmount >= bAmountInCustodian) {
                if (data.b0Amount > 0) {
                    uint256 b0Shortage = (bAmount - bAmountInCustodian) * data.bPrice / UONE;
                    uint256 b0Amount = data.b0Amount.itou();
                    if (b0Amount > b0Shortage) {
                        liquidity = (b0Amount - b0Shortage).rescale(decimalsB0, 18);
                    }
                }
            } else {
                uint256 b0Excessive = (bAmountInCustodian - bAmount) * data.bPrice / UONE * data.collateralFactor / UONE; // discounted
                if (data.b0Amount >= 0) {
                    liquidity = b0Excessive.add(data.b0Amount).rescale(decimalsB0, 18);
                } else {
                    uint256 b0Shortage = (-data.b0Amount).itou();
                    if (b0Excessive > b0Shortage) {
                        liquidity = (b0Excessive - b0Shortage).rescale(decimalsB0, 18);
                    }
                }
            }
        }
    }

    function _deposit(address bToken, uint256 bAmount, uint256 stTotalAmount)
    internal returns (uint256 stMinted)
    {
        if (bAmount != 0) {
            uint256 custodian = _bTokenStates[bToken].getUint(B_CUSTODIAN);
            if (custodian == CUSTODIAN_NONE) {
                if (stTotalAmount == 0) {
                    stMinted = bAmount.rescale(bToken.decimals(), 18);
                } else {
                    stMinted = bAmount * stTotalAmount / (bToken.balanceOfThis() - bAmount);
                }
            }
            else if (custodian == CUSTODIAN_VENUSBNB) {
                stMinted = VenusBnb.deposit(bToken, bAmount, stTotalAmount);
            }
            else if (custodian == CUSTODIAN_AAVEARBITRUM) {
                stMinted = AaveArbitrum.deposit(bToken, bAmount, stTotalAmount);
            }
            else {
                revert InvalidCustodian();
            }
        }
    }

    function _redeem(address bToken, uint256 stAmount, uint256 stTotalAmount)
    internal returns (uint256 bRedeemed)
    {
        if (stTotalAmount != 0 && stAmount != 0) {
            uint256 custodian = _bTokenStates[bToken].getUint(B_CUSTODIAN);
            if (custodian == CUSTODIAN_NONE) {
                bRedeemed = bToken.balanceOfThis() * stAmount / stTotalAmount;
            }
            else if (custodian == CUSTODIAN_VENUSBNB) {
                bRedeemed = VenusBnb.redeem(bToken, stAmount, stTotalAmount);
            }
            else if (custodian == CUSTODIAN_AAVEARBITRUM) {
                bRedeemed = AaveArbitrum.redeem(bToken, stAmount, stTotalAmount);
            }
            else {
                revert InvalidCustodian();
            }
        }
    }

    function _redeemBToken(address bToken, uint256 bAmount, uint256 stTotalAmount)
    internal returns (uint256 stBurned)
    {
        if (stTotalAmount != 0 && bAmount != 0) {
            uint256 custodian = _bTokenStates[bToken].getUint(B_CUSTODIAN);
            if (custodian == CUSTODIAN_NONE) {
                stBurned = bAmount * stTotalAmount / bToken.balanceOfThis();
            }
            else if (custodian == CUSTODIAN_VENUSBNB) {
                stBurned = VenusBnb.redeemBToken(bToken, bAmount, stTotalAmount);
            }
            else if (custodian == CUSTODIAN_AAVEARBITRUM) {
                stBurned = AaveArbitrum.redeemBToken(bToken, bAmount, stTotalAmount);
            }
            else {
                revert InvalidCustodian();
            }
        }
    }

    function _deposit(Data memory data, uint256 bAmount) internal {
        uint256 stMinted = _deposit(data.bToken, bAmount, data.stTotalAmount);
        data.stTotalAmount += stMinted;
        if (data.bToken == tokenB0) {
            uint256 stReserved = stMinted * b0ReserveRatio / UONE;
            uint256 b0Reserved = bAmount * b0ReserveRatio / UONE;
            data.st0Amount += stReserved;
            data.st0TotalAmount = data.stTotalAmount;
            data.stAmount += stMinted - stReserved;
            data.b0Amount += b0Reserved.utoi();
        } else {
            data.stAmount += stMinted;
        }
    }

    function _redeem(Data memory data, uint256 bAmount) internal returns (uint256 bRedeemed) {
        uint256 bAmountInCustodian = data.stAmount * data.stExRate / UONE;
        if (bAmount >= bAmountInCustodian) {
            bRedeemed = _redeem(data.bToken, data.stAmount, data.stTotalAmount);
            data.stTotalAmount -= data.stAmount;
            data.stAmount = 0;
        } else {
            uint256 stBurned = _redeemBToken(data.bToken, bAmount, data.stTotalAmount);
            data.stTotalAmount -= stBurned;
            data.stAmount -= stBurned;
            bRedeemed = bAmount;
        }
        if (data.bToken == tokenB0) {
            data.st0TotalAmount = data.stTotalAmount;
        }
    }

    function _depositReserveB0(Data memory data, uint256 b0Amount) internal {
        uint256 st0Minted = _deposit(tokenB0, b0Amount, data.st0TotalAmount);
        data.st0TotalAmount += st0Minted;
        data.st0Amount += st0Minted;
        if (data.bToken == tokenB0) {
            data.stTotalAmount = data.st0TotalAmount;
        }
    }

    function _redeemReserveB0(Data memory data, uint256 b0Amount) internal returns (uint256 b0Redeemed) {
        uint256 st0ExRate = _getStExRate(tokenB0, data.st0TotalAmount);
        uint256 b0AmountInCustodian = data.st0Amount * st0ExRate / UONE;
        if (b0Amount >= b0AmountInCustodian) {
            b0Redeemed = _redeem(tokenB0, data.st0Amount, data.st0TotalAmount);
            data.st0TotalAmount -= data.st0Amount;
            data.st0Amount = 0;
        } else {
            uint256 st0Burned = _redeemBToken(tokenB0, b0Amount, data.st0TotalAmount);
            data.st0TotalAmount -= st0Burned;
            data.st0Amount -= st0Burned;
            b0Redeemed = b0Amount;
        }
        if (data.bToken == tokenB0) {
            data.stTotalAmount = data.st0TotalAmount;
        }
    }

    function _transferOut(Data memory data, uint256 bAmountOut, bool isTd) internal returns (uint256 bAmount) {
        bAmount = bAmountOut;

        if (bAmount < type(uint256).max / UONE && data.b0Amount < 0) {
            // more bAmount need to be redeemed to cover a negative b0Amount
            if (data.bToken == tokenB0) {
                bAmount += (-data.b0Amount).itou();
            } else {
                bAmount += (-data.b0Amount).itou() * UONE / data.bPrice * 105 / 100; // excessive to cover any possible swap slippage
            }
        }

        bAmount = _redeem(data, bAmount); // bAmount now is the actually bToken redeemed
        uint256 b0AmountIn;  // for b0 goes to reserves
        uint256 b0AmountOut; // for b0 goes to user, (b0AmountIn + b0AmountOut) is the tokenB0 available currently in vault
        uint256 iouAmount; // iou amount goes to trader

        // fill b0Amount hole
        if (bAmount > 0 && data.b0Amount < 0) {
            uint256 owe = (-data.b0Amount).itou();
            uint256 tmpIn;
            if (data.bToken == tokenB0) {
                if (bAmount >= owe) {
                    tmpIn = owe;
                    bAmount -= owe;
                } else {
                    tmpIn = bAmount;
                    bAmount = 0;
                }
            } else if (data.bToken == tokenETH) {
                (uint256 resultB0, uint256 resultBX) = swapper.swapETHForExactB0{value: bAmount}(owe);
                tmpIn = resultB0;
                bAmount -= resultBX;
            } else {
                (uint256 resultB0, uint256 resultBX) = swapper.swapBXForExactB0(data.bToken, owe, bAmount);
                tmpIn = resultB0;
                bAmount -= resultBX;
            }
            b0AmountIn += tmpIn;
            data.b0Amount += tmpIn.utoi();
        }

        // deal excessive
        if (bAmount > bAmountOut) {
            uint256 bExcessive = bAmount - bAmountOut;
            uint256 tmpIn;
            if (data.bToken == tokenB0) {
                tmpIn = bExcessive;
                bAmount -= bExcessive;
            } else if (data.bToken == tokenETH) {
                (uint256 resultB0, uint256 resultBX) = swapper.swapExactETHForB0{value: bExcessive}();
                tmpIn = resultB0;
                bAmount -= resultBX;
            } else {
                (uint256 resultB0, uint256 resultBX) = swapper.swapExactBXForB0(data.bToken, bExcessive);
                tmpIn = resultB0;
                bAmount -= resultBX;
            }
            b0AmountIn += tmpIn;
            data.b0Amount += tmpIn.utoi();
        }

        // deal with reserved portion when withdraw all, or operating token is tokenB0
        if (data.b0Amount > 0) {
            uint256 amount;
            if (bAmountOut >= type(uint256).max / UONE) { // withdraw all
                amount = data.b0Amount.itou();
            } else if (data.bToken == tokenB0 && bAmount < bAmountOut) { // shortage on tokenB0
                amount = SafeMath.min(data.b0Amount.itou(), bAmountOut - bAmount);
            }
            if (amount > 0) {
                uint256 tmpOut;
                if (amount > b0AmountIn) {
                    uint256 b0Redeemed = _redeemReserveB0(data, amount - b0AmountIn);
                    if (isTd && b0Redeemed < amount - b0AmountIn) { // b0 insufficent
                        iouAmount = amount - b0AmountIn - b0Redeemed;
                    }
                    tmpOut = b0AmountIn + b0Redeemed;
                    b0AmountIn = 0;
                } else {
                    tmpOut = amount;
                    b0AmountIn -= amount;
                }
                b0AmountOut += tmpOut;
                data.b0Amount -= tmpOut.utoi() + iouAmount.utoi();
            }
        }

        if (b0AmountIn > 0) {
            _depositReserveB0(data, b0AmountIn);
        }

        // transfer b0, or swap b0 to current operating token
        if (b0AmountOut > 0) {
            if (isTd) {
                if (data.bToken == tokenB0) {
                    bAmount += b0AmountOut;
                } else {
                    tokenB0.transferOut(data.account, b0AmountOut);
                }
            } else {
                if (data.bToken == tokenB0) {
                    bAmount += b0AmountOut;
                } else if (data.bToken == tokenETH) {
                    (, uint256 resultBX) = swapper.swapExactB0ForETH(b0AmountOut);
                    bAmount += resultBX;
                } else {
                    (, uint256 resultBX) = swapper.swapExactB0ForBX(data.bToken, b0AmountOut);
                    bAmount += resultBX;
                }
            }
        }

        if (bAmount > 0) {
            data.bToken.transferOut(data.account, bAmount);
        }

        if (iouAmount > 0) {
            iou.mint(data.account, iouAmount);
        }
    }

    function _updateLiquidity(uint256 lTokenId, uint256 newLiquidity, uint256 newTotalLiquidity) internal {
        (uint256 cumulativeTimePerLiquidity, uint256 cumulativeTime) = getCumulativeTime(lTokenId);
        _vaultStates.set(S_LIQUIDITYTIME, block.timestamp);
        _vaultStates.set(S_TOTALLIQUIDITY, newTotalLiquidity);
        _vaultStates.set(S_CUMULATIVETIMEPERLIQUIDITY, cumulativeTimePerLiquidity);
        _dTokenStates[lTokenId].set(D_LIQUIDITY, newLiquidity);
        _dTokenStates[lTokenId].set(D_CUMULATIVETIME, cumulativeTime);
        _dTokenStates[lTokenId].set(D_LASTCUMULATIVETIMEPERLIQUIDITY, cumulativeTimePerLiquidity);
    }

    function _verifyEventData(bytes memory eventData, bytes memory signature) internal view {
        bytes32 hash = ECDSA.toEthSignedMessageHash(keccak256(eventData));
        if (ECDSA.recover(hash, signature) != eventSigner) {
            revert InvalidSignature();
        }
    }

}
