// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './SafeMath.sol';

library DpmmFutures {

    using SafeMath for int256;

    int256 private constant ONE = 1e18;

    function calculateK(
        int256 alpha,
        int256 indexPrice,
        int256 liquidity
    ) internal pure returns (int256) {
        return liquidity > 0 ? alpha * indexPrice / liquidity : int256(0);
    }

    /// @dev markPrice = theoreticalPrice * (1 + k * netVolume)
    function calculateMarkPrice(
        int256 theoreticalPrice,
        int256 k,
        int256 netVolume
    ) internal pure returns (int256) {
        return theoreticalPrice * (ONE + k * netVolume / ONE) / ONE;
    }

    function calculateCost(
        int256 theoreticalPrice,
        int256 k,
        int256 netVolume,
        int256 tradeVolume
    ) internal pure returns (int256) {
        int256 r = ((netVolume + tradeVolume) ** 2 - netVolume ** 2) / ONE * k / ONE / 2 + tradeVolume;
        return theoreticalPrice * r / ONE;
    }

}
