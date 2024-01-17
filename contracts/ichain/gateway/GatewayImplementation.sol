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
import { GatewayIndex as I } from './GatewayIndex.sol';
import './GatewayHelper.sol';
import './GatewayStorage.sol';

contract GatewayImplementation is GatewayStorage {

    using Bytes32Map for mapping(uint8 => bytes32);
    using ETHAndERC20 for address;
    using SafeMath for uint256;
    using SafeMath for int256;

    error InvalidBToken();
    error InvalidBAmount();
    error InvalidBPrice();
    error InvalidLTokenId();
    error InvalidPTokenId();
    error InvalidRequestId();
    error InsufficientMargin();
    error InvalidSignature();
    error InsufficientB0();
    error InsufficientExecutionFee();

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
        uint256 realMoneyMargin,
        int256  lastCumulativePnlOnEngine,
        int256  cumulativePnlOnGateway,
        uint256 bAmount
    );

    event RequestTrade(
        uint256 requestId,
        uint256 pTokenId,
        uint256 realMoneyMargin,
        int256  lastCumulativePnlOnEngine,
        int256  cumulativePnlOnGateway,
        bytes32 symbolId,
        int256[] tradeParams
    );

    event RequestLiquidate(
        uint256 requestId,
        uint256 pTokenId,
        uint256 realMoneyMargin,
        int256  lastCumulativePnlOnEngine,
        int256  cumulativePnlOnGateway
    );

    event RequestTradeAndRemoveMargin(
        uint256 requestId,
        uint256 pTokenId,
        uint256 realMoneyMargin,
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
        p.vault0 = address(vault0);
        p.iou = address(iou);
        p.tokenB0 = tokenB0;
        p.dChainEventSigner = dChainEventSigner;
        p.b0ReserveRatio = b0ReserveRatio;
        p.liquidationRewardCutRatio = liquidationRewardCutRatio;
        p.minLiquidationReward = minLiquidationReward;
        p.maxLiquidationReward = maxLiquidationReward;
    }

    function getGatewayState() external view returns (IGateway.GatewayState memory s) {
        return GatewayHelper.getGatewayState(_gatewayStates);
    }

    function getBTokenState(address bToken) external view returns (IGateway.BTokenState memory s) {
        return GatewayHelper.getBTokenState(_bTokenStates, bToken);
    }

    function getLpState(uint256 lTokenId) external view returns (IGateway.LpState memory s) {
        return GatewayHelper.getLpState(_bTokenStates, _dTokenStates, lTokenId);
    }

    function getTdState(uint256 pTokenId) external view returns (IGateway.TdState memory s) {
        return GatewayHelper.getTdState(_bTokenStates, _dTokenStates, pTokenId);
    }

    // @notice Calculate Lp's cumulative time, used in liquidity mining reward distributions
    function getCumulativeTime(uint256 lTokenId)
    public view returns (uint256 cumulativeTimePerLiquidity, uint256 cumulativeTime)
    {
        uint256 liquidityTime = _gatewayStates.getUint(I.S_LIQUIDITYTIME);
        uint256 totalLiquidity = _gatewayStates.getUint(I.S_TOTALLIQUIDITY);
        cumulativeTimePerLiquidity = _gatewayStates.getUint(I.S_CUMULATIVETIMEPERLIQUIDITY);
        uint256 liquidity = _dTokenStates[lTokenId].getUint(I.D_LIQUIDITY);
        cumulativeTime = _dTokenStates[lTokenId].getUint(I.D_CUMULATIVETIME);
        uint256 lastCumulativeTimePerLiquidity = _dTokenStates[lTokenId].getUint(I.D_LASTCUMULATIVETIMEPERLIQUIDITY);

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

    function getExecutionFees() public view returns (uint256[] memory fees) {
        return GatewayHelper.getExecutionFees(_executionFees);
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
        GatewayHelper.addBToken(
            _bTokenStates,
            swapper,
            oracle,
            vault0,
            tokenB0,
            bToken,
            vault,
            oracleId,
            collateralFactor
        );
    }

    function delBToken(address bToken) external _onlyAdmin_ {
        GatewayHelper.delBToken(_bTokenStates, bToken);
    }

    // @dev This function can be used to change bToken collateral factor
    function setBTokenParameter(address bToken, uint8 idx, bytes32 value) external _onlyAdmin_ {
        GatewayHelper.setBTokenParameter(_bTokenStates, bToken, idx, value);
    }

    // @notice Set execution fee for actionId
    function setExecutionFee(uint256 actionId, uint256 executionFee) external _onlyAdmin_ {
        GatewayHelper.setExecutionFee(_executionFees, actionId, executionFee);
    }

    function setDChainExecutionFeePerRequest(uint256 dChainExecutionFeePerRequest) external _onlyAdmin_ {
        GatewayHelper.setDChainExecutionFeePerRequest(_gatewayStates, dChainExecutionFeePerRequest);
    }

    // @notic Claim dChain executionFee to account `to`
    function claimDChainExecutionFee(address to) external _onlyAdmin_ {
        GatewayHelper.claimDChainExecutionFee(_gatewayStates, to);
    }

    // @notice Claim unused iChain execution fee for dTokenId
    function claimUnusedIChainExecutionFee(uint256 dTokenId, bool isLp) external {
        GatewayHelper.claimUnusedIChainExecutionFee(
            _gatewayStates,
            _dTokenStates,
            lToken,
            pToken,
            dTokenId,
            isLp
        );
    }

    // @notice Redeem B0 for burning IOU
    function redeemIOU(uint256 b0Amount) external {
        GatewayHelper.redeemIOU(tokenB0, vault0, iou, msg.sender, b0Amount);
    }

    //================================================================================
    // Interactions
    //================================================================================

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

        uint256 ethAmount = _receiveExecutionFee(lTokenId, _executionFees[I.ACTION_REQUESTADDLIQUIDITY]);
        if (bToken == tokenETH) {
            bAmount = ethAmount;
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
    function requestRemoveLiquidity(uint256 lTokenId, address bToken, uint256 bAmount) external payable {
        _checkLTokenIdOwner(lTokenId, msg.sender);

        _receiveExecutionFee(lTokenId, _executionFees[I.ACTION_REQUESTREMOVELIQUIDITY]);
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
     * @param singlePosition The flag whether trader is using singlePosition margin.
     * @return The unique identifier pTokenId.
     */
    function requestAddMargin(uint256 pTokenId, address bToken, uint256 bAmount, bool singlePosition) public payable returns (uint256) {
        if (pTokenId == 0) {
            pTokenId = pToken.mint(msg.sender);
            if (singlePosition) {
                _dTokenStates[pTokenId].set(I.D_SINGLEPOSITION, true);
            }
        } else {
            _checkPTokenIdOwner(pTokenId, msg.sender);
        }
        _checkBTokenInitialized(bToken);

        Data memory data = _getData(msg.sender, pTokenId, bToken);

        if (bToken == tokenETH) {
            if (bAmount > msg.value) {
                revert InvalidBAmount();
            }
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
    function requestRemoveMargin(uint256 pTokenId, address bToken, uint256 bAmount) external payable {
        _checkPTokenIdOwner(pTokenId, msg.sender);

        _receiveExecutionFee(pTokenId, _executionFees[I.ACTION_REQUESTREMOVEMARGIN]);
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
    function requestTrade(uint256 pTokenId, bytes32 symbolId, int256[] calldata tradeParams) public payable {
        _checkPTokenIdOwner(pTokenId, msg.sender);

        _receiveExecutionFee(pTokenId, _executionFees[I.ACTION_REQUESTTRADE]);

        Data memory data = _getData(msg.sender, pTokenId, _dTokenStates[pTokenId].getAddress(I.D_BTOKEN));
        _getExParams(data);
        uint256 realMoneyMargin = _getDTokenLiquidity(data);

        uint256 requestId = _incrementRequestId(pTokenId);
        emit RequestTrade(
            requestId,
            pTokenId,
            realMoneyMargin,
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
        Data memory data = _getData(pToken.ownerOf(pTokenId), pTokenId, _dTokenStates[pTokenId].getAddress(I.D_BTOKEN));
        _getExParams(data);
        uint256 realMoneyMargin = _getDTokenLiquidity(data);

        uint256 requestId = _incrementRequestId(pTokenId);
        emit RequestLiquidate(
            requestId,
            pTokenId,
            realMoneyMargin,
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
     * @param singlePosition The flag whether trader is using singlePosition margin.
     */
    function requestAddMarginAndTrade(
        uint256 pTokenId,
        address bToken,
        uint256 bAmount,
        bytes32 symbolId,
        int256[] calldata tradeParams,
        bool singlePosition
    ) external payable {
        if (bToken == tokenETH) {
            uint256 executionFee = _executionFees[I.ACTION_REQUESTTRADE];
            if (bAmount + executionFee > msg.value) { // revert if bAmount > msg.value - executionFee
                revert InvalidBAmount();
            }
        }
        pTokenId = requestAddMargin(pTokenId, bToken, bAmount, singlePosition);
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
    ) external payable {
        _checkPTokenIdOwner(pTokenId, msg.sender);

        _receiveExecutionFee(pTokenId, _executionFees[I.ACTION_REQUESTTRADEANDREMOVEMARGIN]);
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
        Data memory data = _getData(lToken.ownerOf(v.lTokenId), v.lTokenId, _dTokenStates[v.lTokenId].getAddress(I.D_BTOKEN));
        int256 diff = v.cumulativePnlOnEngine.minusUnchecked(data.lastCumulativePnlOnEngine);
        data.b0Amount += diff.rescaleDown(18, decimalsB0);
        data.lastCumulativePnlOnEngine = v.cumulativePnlOnEngine;

        uint256 bAmountRemoved;
        if (v.bAmountToRemove != 0) {
            _getExParams(data);
            bAmountRemoved = _transferOut(data, v.liquidity == 0 ? type(uint256).max : v.bAmountToRemove, false);
        }

        _saveData(data);

        _transferLastRequestIChainExecutionFee(v.lTokenId, msg.sender);

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
        Data memory data = _getData(pToken.ownerOf(v.pTokenId), v.pTokenId, _dTokenStates[v.pTokenId].getAddress(I.D_BTOKEN));
        int256 diff = v.cumulativePnlOnEngine.minusUnchecked(data.lastCumulativePnlOnEngine);
        data.b0Amount += diff.rescaleDown(18, decimalsB0);
        data.lastCumulativePnlOnEngine = v.cumulativePnlOnEngine;

        _getExParams(data);
        uint256 bAmount = _transferOut(data, v.bAmountToRemove, true);

        if (_getDTokenLiquidity(data) < v.requiredMargin) {
            revert InsufficientMargin();
        }

        _saveData(data);

        _transferLastRequestIChainExecutionFee(v.pTokenId, msg.sender);

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
        Data memory data = _getData(pToken.ownerOf(v.pTokenId), v.pTokenId, _dTokenStates[v.pTokenId].getAddress(I.D_BTOKEN));
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

        {
            uint256 lastRequestIChainExecutionFee = _dTokenStates[v.pTokenId].getUint(I.D_LASTREQUESTICHAINEXECUTIONFEE);
            uint256 cumulativeUnusedIChainExecutionFee = _dTokenStates[v.pTokenId].getUint(I.D_CUMULATIVEUNUSEDICHAINEXECUTIONFEE);
            _dTokenStates[v.pTokenId].del(I.D_LASTREQUESTICHAINEXECUTIONFEE);
            _dTokenStates[v.pTokenId].del(I.D_CUMULATIVEUNUSEDICHAINEXECUTIONFEE);

            uint256 totalIChainExecutionFee = _gatewayStates.getUint(I.S_TOTALICHAINEXECUTIONFEE);
            totalIChainExecutionFee -= lastRequestIChainExecutionFee + cumulativeUnusedIChainExecutionFee;
            _gatewayStates.set(I.S_TOTALICHAINEXECUTIONFEE, totalIChainExecutionFee);
        }

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

        data.cumulativePnlOnGateway = _gatewayStates.getInt(I.S_CUMULATIVEPNLONGATEWAY);
        data.vault = _bTokenStates[bToken].getAddress(I.B_VAULT);

        data.b0Amount = _dTokenStates[dTokenId].getInt(I.D_B0AMOUNT);
        data.lastCumulativePnlOnEngine = _dTokenStates[dTokenId].getInt(I.D_LASTCUMULATIVEPNLONENGINE);

        _checkBTokenConsistency(dTokenId, bToken);
    }

    function _saveData(Data memory data) internal {
        _gatewayStates.set(I.S_CUMULATIVEPNLONGATEWAY, data.cumulativePnlOnGateway);
        _dTokenStates[data.dTokenId].set(I.D_BTOKEN, data.bToken);
        _dTokenStates[data.dTokenId].set(I.D_B0AMOUNT, data.b0Amount);
        _dTokenStates[data.dTokenId].set(I.D_LASTCUMULATIVEPNLONENGINE, data.lastCumulativePnlOnEngine);
    }

    // @notice Check callback's requestId is the same as the current requestId stored for user
    // If a new request is submitted before the callback for last request, requestId will not match,
    // and this callback cannot be executed anymore
    function _checkRequestId(uint256 dTokenId, uint256 requestId) internal {
        uint128 userRequestId = uint128(requestId);
        if (_dTokenStates[dTokenId].getUint(I.D_REQUESTID) != uint256(userRequestId)) {
            revert InvalidRequestId();
        } else {
            // increment requestId so that callback can only be executed once
            _dTokenStates[dTokenId].set(I.D_REQUESTID, uint256(userRequestId + 1));
        }
    }

    // @notice Increment gateway requestId and user requestId
    // and returns the combined requestId for this request
    // The combined requestId contains 2 parts:
    //   * Lower 128 bits stores user's requestId, only increments when request is from this user
    //   * Higher 128 bits stores gateways's requestId, increments for all new requests in this contract
    function _incrementRequestId(uint256 dTokenId) internal returns (uint256) {
        uint128 gatewayRequestId = uint128(_gatewayStates.getUint(I.S_GATEWAYREQUESTID));
        gatewayRequestId += 1;
        _gatewayStates.set(I.S_GATEWAYREQUESTID, uint256(gatewayRequestId));

        uint128 userRequestId = uint128(_dTokenStates[dTokenId].getUint(I.D_REQUESTID));
        userRequestId += 1;
        _dTokenStates[dTokenId].set(I.D_REQUESTID, uint256(userRequestId));

        uint256 requestId = (uint256(gatewayRequestId) << 128) + uint256(userRequestId);
        return requestId;
    }

    function _checkBTokenInitialized(address bToken) internal view {
        if (_bTokenStates[bToken].getAddress(I.B_VAULT) == address(0)) {
            revert InvalidBToken();
        }
    }

    function _checkBTokenConsistency(uint256 dTokenId, address bToken) internal view {
        address preBToken = _dTokenStates[dTokenId].getAddress(I.D_BTOKEN);
        if (preBToken != address(0) && preBToken != bToken) {
            uint256 stAmount = IVault(_bTokenStates[preBToken].getAddress(I.B_VAULT)).stAmounts(dTokenId);
            if (stAmount != 0) {
                revert InvalidBToken();
            }
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

    function _receiveExecutionFee(uint256 dTokenId, uint256 executionFee) internal returns (uint256) {
        uint256 dChainExecutionFee = _gatewayStates.getUint(I.S_DCHAINEXECUTIONFEEPERREQUEST);
        if (msg.value < executionFee) {
            revert InsufficientExecutionFee();
        }
        uint256 iChainExecutionFee = executionFee - dChainExecutionFee;

        uint256 totalIChainExecutionFee = _gatewayStates.getUint(I.S_TOTALICHAINEXECUTIONFEE) + iChainExecutionFee;
        _gatewayStates.set(I.S_TOTALICHAINEXECUTIONFEE,  totalIChainExecutionFee);

        uint256 lastRequestIChainExecutionFee = _dTokenStates[dTokenId].getUint(I.D_LASTREQUESTICHAINEXECUTIONFEE);
        uint256 cumulativeUnusedIChainExecutionFee = _dTokenStates[dTokenId].getUint(I.D_CUMULATIVEUNUSEDICHAINEXECUTIONFEE);
        cumulativeUnusedIChainExecutionFee += lastRequestIChainExecutionFee;
        lastRequestIChainExecutionFee = iChainExecutionFee;
        _dTokenStates[dTokenId].set(I.D_LASTREQUESTICHAINEXECUTIONFEE, lastRequestIChainExecutionFee);
        _dTokenStates[dTokenId].set(I.D_CUMULATIVEUNUSEDICHAINEXECUTIONFEE, cumulativeUnusedIChainExecutionFee);

        return msg.value - executionFee;
    }

    function _transferLastRequestIChainExecutionFee(uint256 dTokenId, address to) internal {
        uint256 lastRequestIChainExecutionFee = _dTokenStates[dTokenId].getUint(I.D_LASTREQUESTICHAINEXECUTIONFEE);

        if (lastRequestIChainExecutionFee > 0) {
            uint256 totalIChainExecutionFee = _gatewayStates.getUint(I.S_TOTALICHAINEXECUTIONFEE);
            totalIChainExecutionFee -= lastRequestIChainExecutionFee;
            _gatewayStates.set(I.S_TOTALICHAINEXECUTIONFEE, totalIChainExecutionFee);

            _dTokenStates[dTokenId].del(I.D_LASTREQUESTICHAINEXECUTIONFEE);

            tokenETH.transferOut(to, lastRequestIChainExecutionFee);
        }
    }

    // @dev bPrice * bAmount / UONE = b0Amount, b0Amount in decimalsB0
    function _getBPrice(address bToken) internal view returns (uint256 bPrice) {
        if (bToken == tokenB0) {
            bPrice = UONE;
        } else {
            uint8 decimalsB = bToken.decimals();
            bPrice = oracle.getValue(_bTokenStates[bToken].getBytes32(I.B_ORACLEID)).itou().rescale(decimalsB, decimalsB0);
            if (bPrice == 0) {
                revert InvalidBPrice();
            }
        }
    }

    function _getExParams(Data memory data) internal view {
        data.collateralFactor = _bTokenStates[data.bToken].getUint(I.B_COLLATERALFACTOR);
        data.bPrice = _getBPrice(data.bToken);
    }

    // @notice Calculate the liquidity (in 18 decimals) associated with current dTokenId
    function _getDTokenLiquidity(Data memory data) internal view returns (uint256 liquidity) {
        uint256 b0AmountInVault = IVault(data.vault).getBalance(data.dTokenId) * data.bPrice / UONE * data.collateralFactor / UONE;
        uint256 b0Shortage = data.b0Amount >= 0 ? 0 : (-data.b0Amount).itou();
        if (b0AmountInVault >= b0Shortage) {
            liquidity = b0AmountInVault.add(data.b0Amount).rescale(decimalsB0, 18);
        }
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
                    if (b0Redeemed < amount - b0AmountIn) { // b0 insufficent
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
        _gatewayStates.set(I.S_LIQUIDITYTIME, block.timestamp);
        _gatewayStates.set(I.S_TOTALLIQUIDITY, newTotalLiquidity);
        _gatewayStates.set(I.S_CUMULATIVETIMEPERLIQUIDITY, cumulativeTimePerLiquidity);
        _dTokenStates[lTokenId].set(I.D_LIQUIDITY, newLiquidity);
        _dTokenStates[lTokenId].set(I.D_CUMULATIVETIME, cumulativeTime);
        _dTokenStates[lTokenId].set(I.D_LASTCUMULATIVETIMEPERLIQUIDITY, cumulativeTimePerLiquidity);
    }

    function _verifyEventData(bytes memory eventData, bytes memory signature) internal view {
        bytes32 hash = ECDSA.toEthSignedMessageHash(keccak256(eventData));
        if (ECDSA.recover(hash, signature) != dChainEventSigner) {
            revert InvalidSignature();
        }
    }

}
