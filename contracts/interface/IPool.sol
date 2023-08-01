// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IPool {

    struct VarOnAddLiquidity {
        uint256 requestId;
        uint256 lTokenId;
        bytes32 stTokenId;
        uint256 stPrice;
        uint256 stAmount;
    }

    struct VarOnRemoveLiquidity {
        uint256 requestId;
        uint256 lTokenId;
        bytes32 stTokenId;
        uint256 stPrice;
        uint256 stAmount;
    }

    struct VarOnRemoveMargin {
        uint256 requestId;
        uint256 pTokenId;
        bytes32 stTokenId;
        uint256 stPrice;
        uint256 stAmount;
        int256  lastCumulativePnl;
    }

    struct VarOnTrade {
        uint256 requestId;
        uint256 pTokenId;
        bytes32 stTokenId;
        uint256 stPrice;
        uint256 stAmount;
        int256 lastCumulativePnl;
        bytes32 symbolId;
        int256[] tradeParams;
    }

    struct VarOnLiquidate {
        uint256 requestId;
        uint256 pTokenId;
        bytes32 stTokenId;
        uint256 stPrice;
        uint256 stAmount;
        int256 lastCumulativePnl;
    }

    struct VarOnPostLiquidate {
        uint256 requestId;
        uint256 pTokenId;
        int256 lastCumulativePnl;
    }

}
