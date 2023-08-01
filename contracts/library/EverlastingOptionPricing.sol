// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './PRBMathSD59x18.sol';

library EverlastingOptionPricing {

    int256 private constant ONE = 1e18;

    // @param S Spot price
    // @param K Strike price
    // @param sigma Volatility
    // @param T Funding period in years
    function getEverlastingTimeValueAndDelta(int256 S, int256 K, int256 sigma, int256 T)
    internal pure returns (int256 timeValue, int256 delta, int256 u)
    {
        int256 u2 = ONE * 8 * ONE / sigma * ONE / sigma * ONE / T + ONE;
        u = PRBMathSD59x18.sqrt(u2);

        int256 x = S * ONE / K;
        if (S > K) {
            timeValue = K * PRBMathSD59x18.pow(x, (ONE - u) / 2) / u;
            delta = (ONE - u) * timeValue / S / 2;
        } else if (S == K) {
            timeValue = K * ONE / u;
            delta = 0;
        } else {
            timeValue = K * PRBMathSD59x18.pow(x, (ONE + u) / 2) / u;
            delta = (ONE + u) * timeValue / S / 2;
        }
    }

    // @param S Spot price
    // @param K Strike price
    // @param sigma Volatility
    function getVega(int256 S, int256 K, int256 sigma, int256 timeValue, int256 u)
    internal pure returns (int256 vega)
    {
        int256 p1 = (ONE - ONE * ONE / u * ONE / u) * timeValue / sigma;
        if (S == K) {
            vega = p1;
        } else {
            int256 lnSK = PRBMathSD59x18.ln(S * ONE / K);
            int256 p2 = lnSK * u / 2 / ONE;
            vega = S > K ? p1 * (ONE + p2) / ONE : p1 * (ONE - p2) / ONE;
        }
    }

}
