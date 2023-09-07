// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './PRBMathSD59x18.sol';

library EverlastingOptionPricing {

    int256 private constant ONE = 1e18;

    /**
     * @notice Calculate the time value and delta of an option based on the Black-Scholes model.
     * @param S The spot price of the underlying asset.
     * @param K The strike price of the option.
     * @param sigma The volatility of the underlying asset.
     * @param T The funding period in years.
     * @return timeValue The time value of the option.
     * @return delta The delta, which measures the sensitivity of the option's price to changes in the spot price.
     * @return u The 'u' parameter used in the calculations.
     */
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

    /**
     * @notice Calculate the Vega, which measures the sensitivity of an option's price to changes in volatility.
     * @param S The spot price of the underlying asset.
     * @param K The strike price of the option.
     * @param sigma The volatility of the underlying asset.
     * @param timeValue The time value of the option.
     * @param u The 'u' parameter used in the calculations.
     * @return vega The Vega of the option.
     */
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
