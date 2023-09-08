// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../vault/IVault.sol';
import './IGateway.sol';
import '../token/IDToken.sol';
import '../token/IIOU.sol';
import '../../oracle/IOracle.sol';
import '../swapper/ISwapper.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '../../library/Bytes32Map.sol';
import '../../library/ETHAndERC20.sol';
import '../../library/SafeMath.sol';
import './GatewayStorage.sol';

contract GatewayImplementation is GatewayStorage {

    using Bytes32Map for mapping(uint8 => bytes32);
    using ETHAndERC20 for address;
    using SafeMath for uint256;
    using SafeMath for int256;

    error CannotDelBToken();
    error BTokenDupInitialize();
    error BTokenNoSwapper();
    error BTokenNoOracle();
    error InvalidBToken();
    error InvalidBAmount();
    error InvalidBPrice();
    error InvalidCustodian();
    error InvalidLTokenId();
    error InvalidPTokenId();
    error InvalidRequestId();
    error InsufficientMargin();
    error InvalidSignature();
    error InsufficientB0();

    event AddBToken(address bToken, address vault, bytes32 oracleId, uint256 collateralFactor);

    event DelBToken(address bToken);

    event UpdateBToken(address bToken);

    event RequestUpdateLiquidity(
        uint256 requestId,
        uint256 lTokenId,
        uint256 liquidity,
        int256  lastCumulativePnlOnEngine,
        int256  cumulativePnlOnGateway,
        uint256 removeBAmount
    );

    event RequestRemoveMargin(
        uint256 requestId,
        uint256 pTokenId,
        uint256 margin,
        int256  lastCumulativePnlOnEngine,
        int256  cumulativePnlOnGateway,
        uint256 bAmount
    );

    event RequestTrade(
        uint256 requestId,
        uint256 pTokenId,
        uint256 margin,
        int256  lastCumulativePnlOnEngine,
        int256  cumulativePnlOnGateway,
        bytes32 symbolId,
        int256[] tradeParams
    );

    event RequestLiquidate(
        uint256 requestId,
        uint256 pTokenId,
        uint256 margin,
        int256  lastCumulativePnlOnEngine,
        int256  cumulativePnlOnGateway
    );

    event RequestTradeAndRemoveMargin(
        uint256 requestId,
        uint256 pTokenId,
        uint256 margin,
        int256  lastCumulativePnlOnEngine,
        int256  cumulativePnlOnGateway,
        uint256 bAmount,
        bytes32 symbolId,
        int256[] tradeParams
    );

    event FinishAddLiquidity(
        uint256 requestId,
        uint256 lTokenId,
        uint256 liquidity,
        uint256 totalLiquidity
    );

    event FinishRemoveLiquidity(
        uint256 requestId,
        uint256 lTokenId,
        uint256 liquidity,
        uint256 totalLiquidity,
        address bToken,
        uint256 bAmount
    );

    event FinishAddMargin(
        uint256 requestId,
        uint256 pTokenId,
        address bToken,
        uint256 bAmount
    );

    event FinishRemoveMargin(
        uint256 requestId,
        uint256 pTokenId,
        address bToken,
        uint256 bAmount
    );

    event FinishLiquidate(
        uint256 requestId,
        uint256 pTokenId,
        int256  lpPnl
    );

    uint8 constant S_CUMULATIVEPNLONGATEWAY     = 1; // Cumulative pnl on Gateway
    uint8 constant S_LIQUIDITYTIME              = 2; // Last timestamp when liquidity updated
    uint8 constant S_TOTALLIQUIDITY             = 3; // Total liquidity on d-chain
    uint8 constant S_CUMULATIVETIMEPERLIQUIDITY = 4; // Cumulavie time per liquidity

    uint8 constant B_VAULT             = 1; // BToken vault address
    uint8 constant B_ORACLEID          = 2; // BToken oracle id
    uint8 constant B_COLLECTERALFACTOR = 3; // BToken collateral factor

    uint8 constant D_REQUESTID                      = 1; // Lp/Trader request id
    uint8 constant D_BTOKEN                         = 2; // Lp/Trader bToken
    uint8 constant D_B0AMOUNT                       = 3; // Lp/Trader b0Amount
    uint8 constant D_LASTCUMULATIVEPNLONENGINE      = 4; // Lp/Trader last cumulative pnl on engine
    uint8 constant D_LIQUIDITY                      = 5; // Lp liquidity
    uint8 constant D_CUMULATIVETIME                 = 6; // Lp cumulative time
    uint8 constant D_LASTCUMULATIVETIMEPERLIQUIDITY = 7; // Lp last cumulative time per liquidity

    uint256 constant UONE = 1e18;
    int256  constant ONE = 1e18;
    address constant tokenETH = address(1);

    IDToken  internal immutable lToken;
    IDToken  internal immutable pToken;
    IOracle  internal immutable oracle;
    ISwapper internal immutable swapper;
    IVault   internal immutable vault0;  // Vault for holding reserved B0, used for payments on regular bases
    IIOU     internal immutable iou;     // IOU ERC20, issued to traders when B0 insufficent
    address  internal immutable tokenB0; // B0, settlement base token, e.g. USDC
    address  internal immutable dChainEventSigner;
    uint8    internal immutable decimalsB0;
    uint256  internal immutable b0ReserveRatio;
    int256   internal immutable liquidationRewardCutRatio;
    int256   internal immutable minLiquidationReward;
    int256   internal immutable maxLiquidationReward;

    constructor (
        address lToken_,
        address pToken_,
        address oracle_,
        address swapper_,
        address vault0_,
        address iou_,
        address tokenB0_,
        address dChainEventSigner_,
        uint256 b0ReserveRatio_,
        int256  liquidationRewardCutRatio_,
        int256  minLiquidationReward_,
        int256  maxLiquidationReward_
    ) {
        lToken = IDToken(lToken_);
        pToken = IDToken(pToken_);
        oracle = IOracle(oracle_);
        swapper = ISwapper(swapper_);
        vault0 = IVault(vault0_);
        iou = IIOU(iou_);
        tokenB0 = tokenB0_;
        decimalsB0 = tokenB0_.decimals();
        dChainEventSigner = dChainEventSigner_;
        b0ReserveRatio = b0ReserveRatio_;
        liquidationRewardCutRatio = liquidationRewardCutRatio_;
        minLiquidationReward = minLiquidationReward_;
        maxLiquidationReward = maxLiquidationReward_;
    }

    //================================================================================
    // Getters
    //================================================================================

    function getGatewayParam() external view returns (IGateway.GatewayParam memory p) {
        p.lToken = address(lToken);
        p.pToken = address(pToken);
        p.oracle = address(oracle);
        p.swapper = address(swapper);
        p.iou = address(iou);
        p.tokenB0 = tokenB0;
        p.dChainEventSigner = dChainEventSigner;
        p.b0ReserveRatio = b0ReserveRatio;
        p.liquidationRewardCutRatio = liquidationRewardCutRatio;
        p.minLiquidationReward = minLiquidationReward;
        p.maxLiquidationReward = maxLiquidationReward;
    }

    function getGatewayState() external view returns (IGateway.GatewayState memory s) {
        s.cumulativePnlOnGateway = _gatewayStates.getInt(S_CUMULATIVEPNLONGATEWAY);
        s.liquidityTime = _gatewayStates.getUint(S_LIQUIDITYTIME);
        s.totalLiquidity = _gatewayStates.getUint(S_TOTALLIQUIDITY);
        s.cumulativeTimePerLiquidity = _gatewayStates.getInt(S_CUMULATIVETIMEPERLIQUIDITY);
    }

    function getBTokenState(address bToken) external view returns (IGateway.BTokenState memory s) {
        s.vault = _bTokenStates[bToken].getAddress(B_VAULT);
        s.oracleId = _bTokenStates[bToken].getBytes32(B_ORACLEID);
        s.collateralFactor = _bTokenStates[bToken].getUint(B_COLLECTERALFACTOR);
    }

    function getLpState(uint256 lTokenId) external view returns (IGateway.LpState memory s) {
        s.requestId = _dTokenStates[lTokenId].getUint(D_REQUESTID);
        s.bToken = _dTokenStates[lTokenId].getAddress(D_BTOKEN);
        s.bAmount = IVault(_bTokenStates[s.bToken].getAddress(B_VAULT)).getBalance(lTokenId);
        s.b0Amount = _dTokenStates[lTokenId].getInt(D_B0AMOUNT);
        s.lastCumulativePnlOnEngine = _dTokenStates[lTokenId].getInt(D_LASTCUMULATIVEPNLONENGINE);
        s.liquidity = _dTokenStates[lTokenId].getUint(D_LIQUIDITY);
        s.cumulativeTime = _dTokenStates[lTokenId].getUint(D_CUMULATIVETIME);
        s.lastCumulativeTimePerLiquidity = _dTokenStates[lTokenId].getUint(D_LASTCUMULATIVETIMEPERLIQUIDITY);
    }

    function getTdState(uint256 pTokenId) external view returns (IGateway.TdState memory s) {
        s.requestId = _dTokenStates[pTokenId].getUint(D_REQUESTID);
        s.bToken = _dTokenStates[pTokenId].getAddress(D_BTOKEN);
        s.bAmount = IVault(_bTokenStates[s.bToken].getAddress(B_VAULT)).getBalance(pTokenId);
        s.b0Amount = _dTokenStates[pTokenId].getInt(D_B0AMOUNT);
        s.lastCumulativePnlOnEngine = _dTokenStates[pTokenId].getInt(D_LASTCUMULATIVEPNLONENGINE);
    }

    // @notice Calculate Lp's cumulative time, used in liquidity mining reward distributions
    function getCumulativeTime(uint256 lTokenId)
    public view returns (uint256 cumulativeTimePerLiquidity, uint256 cumulativeTime)
    {
        uint256 liquidityTime = _gatewayStates.getUint(S_LIQUIDITYTIME);
        uint256 totalLiquidity = _gatewayStates.getUint(S_TOTALLIQUIDITY);
        cumulativeTimePerLiquidity = _gatewayStates.getUint(S_CUMULATIVETIMEPERLIQUIDITY);
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
        address vault,
        bytes32 oracleId,
        uint256 collateralFactor
    ) external _onlyAdmin_ {
        if (_bTokenStates[bToken].getAddress(B_VAULT) != address(0)) {
            revert BTokenDupInitialize();
        }
        if (IVault(vault).asset() != bToken) {
            revert InvalidBToken();
        }
        if (bToken != tokenETH) {
            if (!swapper.isSupportedToken(bToken)) {
                revert BTokenNoSwapper();
            }
            // Approve for swapper and vault
            bToken.approveMax(address(swapper));
            bToken.approveMax(vault);
            if (bToken == tokenB0) {
                // The reserved portion for B0 will be deposited to vault0
                bToken.approveMax(address(vault0));
            }
        }
        // Check bToken oracle except B0
        if (bToken != tokenB0 && oracle.getValue(oracleId) == 0) {
            revert BTokenNoOracle();
        }
        _bTokenStates[bToken].set(B_VAULT, vault);
        _bTokenStates[bToken].set(B_ORACLEID, oracleId);
        _bTokenStates[bToken].set(B_COLLECTERALFACTOR, collateralFactor);

        emit AddBToken(bToken, vault, oracleId, collateralFactor);
    }

    function delBToken(address bToken) external _onlyAdmin_ {
        // bToken can only be deleted when there is no deposits
        if (IVault(_bTokenStates[bToken].getAddress(B_VAULT)).stTotalAmount() != 0) {
            revert CannotDelBToken();
        }

        _bTokenStates[bToken].del(B_VAULT);
        _bTokenStates[bToken].del(B_ORACLEID);
        _bTokenStates[bToken].del(B_COLLECTERALFACTOR);

        emit DelBToken(bToken);
    }

    // @dev This function can be used to change bToken collateral factor
    function setBTokenParameter(address bToken, uint8 idx, bytes32 value) external _onlyAdmin_ {
        _bTokenStates[bToken].set(idx, value);
        emit UpdateBToken(bToken);
    }

    //================================================================================
    // Interactions
    //================================================================================

    // @notice Redeem B0 for burning IOU
    function redeemIOU(uint256 b0Amount) external {
        if (b0Amount > 0) {
            uint256 b0Redeemed = vault0.redeem(uint256(0), b0Amount);
            if (b0Redeemed > 0) {
                iou.burn(msg.sender, b0Redeemed);
                tokenB0.transferOut(msg.sender, b0Redeemed);
            }
        }
    }

    /**
     * @notice Request to add liquidity with specified base token.
     * @param lTokenId The unique identifier of the LToken.
     * @param bToken The address of the base token to add as liquidity.
     * @param bAmount The amount of base tokens to add as liquidity.
     */
    function requestAddLiquidity(uint256 lTokenId, address bToken, uint256 bAmount) external payable {
        if (lTokenId == 0) {
            lTokenId = lToken.mint(msg.sender);
        } else {
            _checkLTokenIdOwner(lTokenId, msg.sender);
        }
        _checkBTokenInitialized(bToken);

        Data memory data = _getData(msg.sender, lTokenId, bToken);

        if (bToken == tokenETH) {
            bAmount = msg.value;
        }
        if (bAmount == 0) {
            revert InvalidBAmount();
        }
        if (bToken != tokenETH) {
            bToken.transferIn(data.account, bAmount);
        }

        _deposit(data, bAmount);
        _getExParams(data);
        uint256 newLiquidity = _getDTokenLiquidity(data);

        _saveData(data);

        uint256 requestId = _incrementRequestId(lTokenId);
        emit RequestUpdateLiquidity(
            requestId,
            lTokenId,
            newLiquidity,
            data.lastCumulativePnlOnEngine,
            data.cumulativePnlOnGateway,
            0
        );
    }

    /**
     * @notice Request to remove liquidity with specified base token.
     * @param lTokenId The unique identifier of the LToken.
     * @param bToken The address of the base token to remove as liquidity.
     * @param bAmount The amount of base tokens to remove as liquidity.
     */
    function requestRemoveLiquidity(uint256 lTokenId, address bToken, uint256 bAmount) external {
        _checkLTokenIdOwner(lTokenId, msg.sender);

        if (bAmount == 0) {
            revert InvalidBAmount();
        }

        Data memory data = _getData(msg.sender, lTokenId, bToken);
        _getExParams(data);
        uint256 oldLiquidity = _getDTokenLiquidity(data);
        uint256 newLiquidity = _getDTokenLiquidityWithRemove(data, bAmount);
        if (newLiquidity <= oldLiquidity / 100) {
            newLiquidity = 0;
        }

        uint256 requestId = _incrementRequestId(lTokenId);
        emit RequestUpdateLiquidity(
            requestId,
            lTokenId,
            newLiquidity,
            data.lastCumulativePnlOnEngine,
            data.cumulativePnlOnGateway,
            bAmount
        );
    }

    /**
     * @notice Request to add margin with specified base token.
     * @param pTokenId The unique identifier of the PToken.
     * @param bToken The address of the base token to add as margin.
     * @param bAmount The amount of base tokens to add as margin.
     * @return The unique identifier pTokenId.
     */
    function requestAddMargin(uint256 pTokenId, address bToken, uint256 bAmount) public payable returns (uint256) {
        if (pTokenId == 0) {
            pTokenId = pToken.mint(msg.sender);
        } else {
            _checkPTokenIdOwner(pTokenId, msg.sender);
        }
        _checkBTokenInitialized(bToken);

        Data memory data = _getData(msg.sender, pTokenId, bToken);

        if (bToken == tokenETH) {
            bAmount = msg.value;
        }
        if (bAmount == 0) {
            revert InvalidBAmount();
        }
        if (bToken != tokenETH) {
            bToken.transferIn(data.account, bAmount);
        }

        _deposit(data, bAmount);

        _saveData(data);

        uint256 requestId = _incrementRequestId(pTokenId);
        emit FinishAddMargin(
            requestId,
            pTokenId,
            bToken,
            bAmount
        );

        return pTokenId;
    }

    /**
     * @notice Request to remove margin with specified base token.
     * @param pTokenId The unique identifier of the PToken.
     * @param bToken The address of the base token to remove as margin.
     * @param bAmount The amount of base tokens to remove as margin.
     */
    function requestRemoveMargin(uint256 pTokenId, address bToken, uint256 bAmount) external {
        _checkPTokenIdOwner(pTokenId, msg.sender);

        if (bAmount == 0) {
            revert InvalidBAmount();
        }

        Data memory data = _getData(msg.sender, pTokenId, bToken);
        _getExParams(data);
        uint256 oldMargin = _getDTokenLiquidity(data);
        uint256 newMargin = _getDTokenLiquidityWithRemove(data, bAmount);
        if (newMargin <= oldMargin / 100) {
            newMargin = 0;
        }

        uint256 requestId = _incrementRequestId(pTokenId);
        emit RequestRemoveMargin(
            requestId,
            pTokenId,
            newMargin,
            data.lastCumulativePnlOnEngine,
            data.cumulativePnlOnGateway,
            bAmount
        );
    }

    /**
     * @notice Request to initiate a trade using a specified PToken, symbol identifier, and trade parameters.
     * @param pTokenId The unique identifier of the PToken.
     * @param symbolId The identifier of the trading symbol.
     * @param tradeParams An array of trade parameters for the trade execution.
     */
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
            data.cumulativePnlOnGateway,
            symbolId,
            tradeParams
        );
    }

    /**
     * @notice Request to liquidate a specified PToken.
     * @param pTokenId The unique identifier of the PToken.
     */
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
            data.cumulativePnlOnGateway
        );
    }

    /**
     * @notice Request to add margin and initiate a trade in a single transaction.
     * @param pTokenId The unique identifier of the PToken.
     * @param bToken The address of the base token to add as margin.
     * @param bAmount The amount of base tokens to add as margin.
     * @param symbolId The identifier of the trading symbol for the trade.
     * @param tradeParams An array of trade parameters for the trade execution.
     */
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

    /**
     * @notice Request to initiate a trade and simultaneously remove margin from a specified PToken.
     * @param pTokenId The unique identifier of the PToken.
     * @param bToken The address of the base token to remove as margin.
     * @param bAmount The amount of base tokens to remove as margin.
     * @param symbolId The identifier of the trading symbol for the trade.
     * @param tradeParams An array of trade parameters for the trade execution.
     */
    function requestTradeAndRemoveMargin(
        uint256 pTokenId,
        address bToken,
        uint256 bAmount,
        bytes32 symbolId,
        int256[] calldata tradeParams
    ) external {
        _checkPTokenIdOwner(pTokenId, msg.sender);

        if (bAmount == 0) {
            revert InvalidBAmount();
        }

        Data memory data = _getData(msg.sender, pTokenId, bToken);
        _getExParams(data);
        uint256 oldMargin = _getDTokenLiquidity(data);
        uint256 newMargin = _getDTokenLiquidityWithRemove(data, bAmount);
        if (newMargin <= oldMargin / 100) {
            newMargin = 0;
        }

        uint256 requestId = _incrementRequestId(pTokenId);
        emit RequestTradeAndRemoveMargin(
            requestId,
            pTokenId,
            newMargin,
            data.lastCumulativePnlOnEngine,
            data.cumulativePnlOnGateway,
            bAmount,
            symbolId,
            tradeParams
        );
    }

    /**
     * @notice Finalize the liquidity update based on event emitted on d-chain.
     * @param eventData The encoded event data containing information about the liquidity update, emitted on d-chain.
     * @param signature The signature used to verify the event data.
     */
    function finishUpdateLiquidity(bytes memory eventData, bytes memory signature) external _reentryLock_ {
        _verifyEventData(eventData, signature);
        IGateway.VarOnExecuteUpdateLiquidity memory v = abi.decode(eventData, (IGateway.VarOnExecuteUpdateLiquidity));
        _checkRequestId(v.lTokenId, v.requestId);

        _updateLiquidity(v.lTokenId, v.liquidity, v.totalLiquidity);

        // Cumulate unsettled PNL to b0Amount
        Data memory data = _getData(lToken.ownerOf(v.lTokenId), v.lTokenId, _dTokenStates[v.lTokenId].getAddress(D_BTOKEN));
        int256 diff = v.cumulativePnlOnEngine.minusUnchecked(data.lastCumulativePnlOnEngine);
        data.b0Amount += diff.rescaleDown(18, decimalsB0);
        data.lastCumulativePnlOnEngine = v.cumulativePnlOnEngine;

        uint256 bAmountRemoved;
        if (v.bAmountToRemove != 0) {
            _getExParams(data);
            bAmountRemoved = _transferOut(data, v.liquidity == 0 ? type(uint256).max : v.bAmountToRemove, false);
        }

        _saveData(data);

        if (v.bAmountToRemove == 0) {
            // If bAmountToRemove == 0, it is a AddLiqudiity finalization
            emit FinishAddLiquidity(
                v.requestId,
                v.lTokenId,
                v.liquidity,
                v.totalLiquidity
            );
        } else {
            // If bAmountToRemove != 0, it is a RemoveLiquidity finalization
            emit FinishRemoveLiquidity(
                v.requestId,
                v.lTokenId,
                v.liquidity,
                v.totalLiquidity,
                data.bToken,
                bAmountRemoved
            );
        }
    }

    /**
     * @notice Finalize the remove of margin based on event emitted on d-chain.
     * @param eventData The encoded event data containing information about the margin remove, emitted on d-chain.
     * @param signature The signature used to verify the event data.
     */
    function finishRemoveMargin(bytes memory eventData, bytes memory signature) external _reentryLock_ {
        _verifyEventData(eventData, signature);
        IGateway.VarOnExecuteRemoveMargin memory v = abi.decode(eventData, (IGateway.VarOnExecuteRemoveMargin));
        _checkRequestId(v.pTokenId, v.requestId);

        // Cumulate unsettled PNL to b0Amount
        Data memory data = _getData(pToken.ownerOf(v.pTokenId), v.pTokenId, _dTokenStates[v.pTokenId].getAddress(D_BTOKEN));
        int256 diff = v.cumulativePnlOnEngine.minusUnchecked(data.lastCumulativePnlOnEngine);
        data.b0Amount += diff.rescaleDown(18, decimalsB0);
        data.lastCumulativePnlOnEngine = v.cumulativePnlOnEngine;

        _getExParams(data);
        uint256 bAmount = _transferOut(data, v.bAmountToRemove, true);

        if (_getDTokenLiquidity(data) < v.requiredMargin) {
            revert InsufficientMargin();
        }

        _saveData(data);

        emit FinishRemoveMargin(
            v.requestId,
            v.pTokenId,
            data.bToken,
            bAmount
        );
    }

    /**
     * @notice Finalize the liquidation based on event emitted on d-chain.
     * @param eventData The encoded event data containing information about the liquidation, emitted on d-chain.
     * @param signature The signature used to verify the event data.
     */
    function finishLiquidate(bytes memory eventData, bytes memory signature) external _reentryLock_ {
        _verifyEventData(eventData, signature);
        IGateway.VarOnExecuteLiquidate memory v = abi.decode(eventData, (IGateway.VarOnExecuteLiquidate));

        // Cumulate unsettled PNL to b0Amount
        Data memory data = _getData(pToken.ownerOf(v.pTokenId), v.pTokenId, _dTokenStates[v.pTokenId].getAddress(D_BTOKEN));
        int256 diff = v.cumulativePnlOnEngine.minusUnchecked(data.lastCumulativePnlOnEngine);
        data.b0Amount += diff.rescaleDown(18, decimalsB0);
        data.lastCumulativePnlOnEngine = v.cumulativePnlOnEngine;

        uint256 b0AmountIn;

        // Redeem all bToken from vault and swap into B0
        {
            uint256 bAmount = IVault(data.vault).redeem(data.dTokenId, type(uint256).max);
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

        int256 lpPnl = b0AmountIn.utoi() + data.b0Amount; // All Lp's PNL by liquidating this trader
        int256 reward;

        // Calculate liquidator's reward
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
                uint256 b0Redeemed = vault0.redeem(uint256(0), uReward - b0AmountIn);
                tokenB0.transferOut(msg.sender, b0AmountIn + b0Redeemed);
                reward = (b0AmountIn + b0Redeemed).utoi();
                b0AmountIn = 0;
            }

            lpPnl -= reward;
        }

        if (b0AmountIn > 0) {
            vault0.deposit(uint256(0), b0AmountIn);
        }

        // Cumulate lpPnl into cumulativePnlOnGateway,
        // which will be distributed to all LPs on all i-chains with next request process
        data.cumulativePnlOnGateway = data.cumulativePnlOnGateway.addUnchecked(lpPnl.rescale(decimalsB0, 18));
        data.b0Amount = 0;
        _saveData(data);
        pToken.burn(v.pTokenId);

        emit FinishLiquidate(
            v.requestId,
            v.pTokenId,
            lpPnl
        );
    }

    //================================================================================
    // Internals
    //================================================================================

    // Temporary struct holding intermediate values passed around functions
    struct Data {
        address account;                   // Lp/Trader account address
        uint256 dTokenId;                  // Lp/Trader dTokenId
        address bToken;                    // Lp/Trader bToken address

        int256  cumulativePnlOnGateway;    // cumulative pnl on Gateway
        address vault;                     // Lp/Trader bToken's vault address

        int256  b0Amount;                  // Lp/Trader b0Amount
        int256  lastCumulativePnlOnEngine; // Lp/Trader last cumulative pnl on engine

        uint256 collateralFactor;          // bToken collateral factor
        uint256 bPrice;                    // bToken price
    }

    function _getData(address account, uint256 dTokenId, address bToken) internal view returns (Data memory data) {
        data.account = account;
        data.dTokenId = dTokenId;
        data.bToken = bToken;

        data.cumulativePnlOnGateway = _gatewayStates.getInt(S_CUMULATIVEPNLONGATEWAY);
        data.vault = _bTokenStates[bToken].getAddress(B_VAULT);

        data.b0Amount = _dTokenStates[dTokenId].getInt(D_B0AMOUNT);
        data.lastCumulativePnlOnEngine = _dTokenStates[dTokenId].getInt(D_LASTCUMULATIVEPNLONENGINE);

        if (IVault(data.vault).stAmounts(dTokenId) != 0) {
            _checkBTokenConsistency(dTokenId, bToken);
        }
    }

    function _saveData(Data memory data) internal {
        _gatewayStates.set(S_CUMULATIVEPNLONGATEWAY, data.cumulativePnlOnGateway);
        _dTokenStates[data.dTokenId].set(D_BTOKEN, data.bToken);
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
        if (_bTokenStates[bToken].getAddress(B_VAULT) == address(0)) {
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

    // @dev bPrice * bAmount / UONE = b0Amount, b0Amount in decimalsB0
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
        data.bPrice = _getBPrice(data.bToken);
    }

    // @notice Calculate the liquidity (in 18 decimals) associated with current dTokenId
    function _getDTokenLiquidity(Data memory data) internal view returns (uint256 liquidity) {
        uint256 liquidityInB0 = (
            IVault(data.vault).getBalance(data.dTokenId) * data.bPrice / UONE * data.collateralFactor / UONE
        ).add(data.b0Amount);
        return liquidityInB0.rescale(decimalsB0, 18);
    }

    // @notice Calculate the liquidity (in 18 decimals) associated with current dTokenId if `bAmount` in bToken is removed
    function _getDTokenLiquidityWithRemove(Data memory data, uint256 bAmount) internal view returns (uint256 liquidity) {
        if (bAmount < type(uint256).max / data.bPrice) { // make sure bAmount * bPrice won't overflow
            uint256 bAmountInVault = IVault(data.vault).getBalance(data.dTokenId);
            if (bAmount >= bAmountInVault) {
                if (data.b0Amount > 0) {
                    uint256 b0Shortage = (bAmount - bAmountInVault) * data.bPrice / UONE;
                    uint256 b0Amount = data.b0Amount.itou();
                    if (b0Amount > b0Shortage) {
                        liquidity = (b0Amount - b0Shortage).rescale(decimalsB0, 18);
                    }
                }
            } else {
                uint256 b0Excessive = (bAmountInVault - bAmount) * data.bPrice / UONE * data.collateralFactor / UONE; // discounted
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

    // @notice Deposit bToken with `bAmount`
    function _deposit(Data memory data, uint256 bAmount) internal {
        if (data.bToken == tokenB0) {
            uint256 reserved = bAmount * b0ReserveRatio / UONE;
            bAmount -= reserved;
            vault0.deposit(uint256(0), reserved);
            data.b0Amount += reserved.utoi();
        }
        if (data.bToken == tokenETH) {
            IVault(data.vault).deposit{value: bAmount}(data.dTokenId, bAmount);
        } else {
            IVault(data.vault).deposit(data.dTokenId, bAmount);
        }
    }

    /**
     * @notice Transfer a specified amount of bToken, handling various cases.
     * @param data A Data struct containing information about the interaction.
     * @param bAmountOut The intended amount of tokens to transfer out.
     * @param isTd A flag indicating whether the transfer is for a trader (true) or not (false).
     * @return bAmount The amount of tokens actually transferred.
     */
    function _transferOut(Data memory data, uint256 bAmountOut, bool isTd) internal returns (uint256 bAmount) {
        bAmount = bAmountOut;

        // Handle redemption of additional tokens to cover a negative B0 amount.
        if (bAmount < type(uint256).max / UONE && data.b0Amount < 0) {
            if (data.bToken == tokenB0) {
                // Redeem B0 tokens to cover the negative B0 amount.
                bAmount += (-data.b0Amount).itou();
            } else {
                // Swap tokens to B0 to cover the negative B0 amount, with a slight excess to account for possible slippage.
                bAmount += (-data.b0Amount).itou() * UONE / data.bPrice * 105 / 100;
            }
        }

        // Redeem tokens from the vault using IVault interface.
        bAmount = IVault(data.vault).redeem(data.dTokenId, bAmount); // bAmount now represents the actual redeemed bToken.

        uint256 b0AmountIn;  // Amount of B0 tokens going to reserves.
        uint256 b0AmountOut; // Amount of B0 tokens going to the user.
        uint256 iouAmount;   // Amount of IOU tokens going to the trader.

        // Handle excessive tokens (more than bAmountOut).
        if (bAmount > bAmountOut) {
            uint256 bExcessive = bAmount - bAmountOut;
            uint256 b0Excessive;
            if (data.bToken == tokenB0) {
                b0Excessive = bExcessive;
                bAmount -= bExcessive;
            } else if (data.bToken == tokenETH) {
                (uint256 resultB0, uint256 resultBX) = swapper.swapExactETHForB0{value: bExcessive}();
                b0Excessive = resultB0;
                bAmount -= resultBX;
            } else {
                (uint256 resultB0, uint256 resultBX) = swapper.swapExactBXForB0(data.bToken, bExcessive);
                b0Excessive = resultB0;
                bAmount -= resultBX;
            }
            b0AmountIn += b0Excessive;
            data.b0Amount += b0Excessive.utoi();
        }

        // Handle filling the negative B0 balance, by swapping bToken into B0, if necessary.
        if (bAmount > 0 && data.b0Amount < 0) {
            uint256 owe = (-data.b0Amount).itou();
            uint256 b0Fill;
            if (data.bToken == tokenB0) {
                if (bAmount >= owe) {
                    b0Fill = owe;
                    bAmount -= owe;
                } else {
                    b0Fill = bAmount;
                    bAmount = 0;
                }
            } else if (data.bToken == tokenETH) {
                (uint256 resultB0, uint256 resultBX) = swapper.swapETHForExactB0{value: bAmount}(owe);
                b0Fill = resultB0;
                bAmount -= resultBX;
            } else {
                (uint256 resultB0, uint256 resultBX) = swapper.swapBXForExactB0(data.bToken, owe, bAmount);
                b0Fill = resultB0;
                bAmount -= resultBX;
            }
            b0AmountIn += b0Fill;
            data.b0Amount += b0Fill.utoi();
        }

        // Handle reserved portion when withdrawing all or operating token is tokenB0
        if (data.b0Amount > 0) {
            uint256 amount;
            if (bAmountOut >= type(uint256).max / UONE) { // withdraw all
                amount = data.b0Amount.itou();
            } else if (data.bToken == tokenB0 && bAmount < bAmountOut) { // shortage on tokenB0
                amount = SafeMath.min(data.b0Amount.itou(), bAmountOut - bAmount);
            }
            if (amount > 0) {
                uint256 b0Out;
                if (amount > b0AmountIn) {
                    // Redeem B0 tokens from vault0
                    uint256 b0Redeemed = vault0.redeem(uint256(0), amount - b0AmountIn);
                    if (b0Redeemed < amount - b0AmountIn) { // b0 insufficent for trader
                        if (isTd) {
                            iouAmount = amount - b0AmountIn - b0Redeemed; // Issue IOU for trader when B0 insufficent
                        } else {
                            revert InsufficientB0(); // Revert for Lp when B0 insufficent
                        }
                    }
                    b0Out = b0AmountIn + b0Redeemed;
                    b0AmountIn = 0;
                } else {
                    b0Out = amount;
                    b0AmountIn -= amount;
                }
                b0AmountOut += b0Out;
                data.b0Amount -= b0Out.utoi() + iouAmount.utoi();
            }
        }

        // Deposit B0 tokens into the vault0, if any
        if (b0AmountIn > 0) {
            vault0.deposit(uint256(0), b0AmountIn);
        }

        // Transfer B0 tokens or swap them to the current operating token
        if (b0AmountOut > 0) {
            if (isTd) {
                // No swap from B0 to BX for trader
                if (data.bToken == tokenB0) {
                    bAmount += b0AmountOut;
                } else {
                    tokenB0.transferOut(data.account, b0AmountOut);
                }
            } else {
                // Swap B0 into BX for Lp
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

        // Transfer the remaining bAmount to the user's account.
        if (bAmount > 0) {
            data.bToken.transferOut(data.account, bAmount);
        }

        // Mint IOU tokens for the trader, if any.
        if (iouAmount > 0) {
            iou.mint(data.account, iouAmount);
        }
    }

    /**
     * @dev Update liquidity-related state variables for a specific `lTokenId`.
     * @param lTokenId The ID of the corresponding lToken.
     * @param newLiquidity The new liquidity amount for the lToken.
     * @param newTotalLiquidity The new total liquidity in the engine.
     */
    function _updateLiquidity(uint256 lTokenId, uint256 newLiquidity, uint256 newTotalLiquidity) internal {
        (uint256 cumulativeTimePerLiquidity, uint256 cumulativeTime) = getCumulativeTime(lTokenId);
        _gatewayStates.set(S_LIQUIDITYTIME, block.timestamp);
        _gatewayStates.set(S_TOTALLIQUIDITY, newTotalLiquidity);
        _gatewayStates.set(S_CUMULATIVETIMEPERLIQUIDITY, cumulativeTimePerLiquidity);
        _dTokenStates[lTokenId].set(D_LIQUIDITY, newLiquidity);
        _dTokenStates[lTokenId].set(D_CUMULATIVETIME, cumulativeTime);
        _dTokenStates[lTokenId].set(D_LASTCUMULATIVETIMEPERLIQUIDITY, cumulativeTimePerLiquidity);
    }

    function _verifyEventData(bytes memory eventData, bytes memory signature) internal view {
        bytes32 hash = ECDSA.toEthSignedMessageHash(keccak256(eventData));
        if (ECDSA.recover(hash, signature) != dChainEventSigner) {
            revert InvalidSignature();
        }
    }

}
