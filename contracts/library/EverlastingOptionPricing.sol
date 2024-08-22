// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './PRBMathSD59x18.sol';

library EverlastingOptionPricing {

    int256 private constant ONE = 1e18;

    int256 private constant r = 1095000000000000000; // Interest rate: 109.5%, 0.3% per day

    int256 private constant T = 19178082191780822; // Funding Period: 7 / 365, 7 days

    int256 private constant sqrtT = 138484952943562868; // sqrt(T)

    int256 private constant sqrt2 = 1414213562373095049; // sqrt(2)

    int256 private constant onePlusRT = 1021000000000000000; // 1 + rT

    int256 private constant sqrt2MulOnePlusRT = 1428985654231700116; // sqrt(2(1 + rT))

    struct Tmp {
        int256 x;
        int256 p;
        int256 q;
        int256 u;
        int256 w;
        int256 A;
        int256 B;
        int256 SAKB;
        int256 dVdS;
        int256 t1;
        int256 t2;
    }
    /**
     * @notice Calculate the time value and delta of an option based on the Black-Scholes model.
     * @param S The spot price of the underlying asset.
     * @param K The strike price of the option.
     * @param sigma The volatility of the underlying asset.
     */
    function calculateEverlastingOption(int256 S, int256 K, int256 sigma, bool isCall)
    internal pure returns (
        int256 theoreticalValue,
        int256 intrinsicValue,
        int256 delta,
        int256 gamma
    )
    {
        Tmp memory tmp;

        tmp.x = 2 * r * ONE / sigma * ONE / sigma;
        tmp.p = ONE + tmp.x;
        tmp.q = ONE - tmp.x;

        tmp.x = sigma * sqrtT / ONE * tmp.p / sqrt2 / 2;
        tmp.u = ONE * ONE / tmp.x + tmp.x / 2 + tmp.x * tmp.x / ONE * tmp.x / ONE / 8;
        tmp.x = sigma * sqrtT / ONE * tmp.q / sqrt2MulOnePlusRT / 2;
        tmp.w = -(ONE * ONE / tmp.x + tmp.x / 2 + tmp.x * tmp.x / ONE * tmp.x / ONE / 8);

        tmp.x = S * ONE / K;
        if (S >= K) {
            tmp.A = PRBMathSD59x18.pow(tmp.x, -tmp.p * (ONE + tmp.u) / ONE / 2) * (ONE - tmp.u) / tmp.u / 2;
            tmp.B = PRBMathSD59x18.pow(tmp.x, tmp.q * (ONE + tmp.w) / ONE / 2) * (ONE - tmp.w) / tmp.w / 2 * ONE / onePlusRT;

            tmp.SAKB = (S * tmp.A - K * tmp.B) / ONE;
            tmp.dVdS = tmp.A * (ONE - (ONE + tmp.u) * tmp.p / ONE / 2) / ONE - tmp.B * K / S * ((ONE + tmp.w) * tmp.q / ONE / 2) / ONE;

            if (isCall) {
                theoreticalValue = tmp.SAKB + (S - K * ONE / onePlusRT);
                intrinsicValue = (S - K) * ONE / onePlusRT;
                delta = tmp.dVdS + ONE;
            } else {
                theoreticalValue = tmp.SAKB;
                intrinsicValue = 0;
                delta = tmp.dVdS;
            }

            tmp.t1 = (ONE + tmp.u) * tmp.p / ONE / 2;
            tmp.t2 = (ONE + tmp.w) * tmp.q / ONE / 2;
            gamma = tmp.A * (tmp.t1 - ONE) / S * tmp.t1 / ONE - tmp.B * K / S * (tmp.t2 - ONE) / S * tmp.t2 / ONE;
        } else {
            tmp.A = PRBMathSD59x18.pow(tmp.x, -tmp.p * (ONE - tmp.u) / ONE / 2) * (ONE + tmp.u) / tmp.u / 2;
            tmp.B = PRBMathSD59x18.pow(tmp.x, tmp.q * (ONE - tmp.w) / ONE / 2) * (ONE + tmp.w) / tmp.w / 2 * ONE / onePlusRT;

            tmp.SAKB = (S * tmp.A - K * tmp.B) / ONE;
            tmp.dVdS = tmp.A * (ONE - (ONE - tmp.u) * tmp.p / ONE / 2) / ONE - tmp.B * K / S * ((ONE - tmp.w) * tmp.q / ONE / 2) / ONE;

            if (isCall) {
                theoreticalValue = tmp.SAKB;
                intrinsicValue = 0;
                delta = tmp.dVdS;
            } else {
                theoreticalValue = tmp.SAKB - (S - K * ONE / onePlusRT);
                intrinsicValue = (K - S) * ONE / onePlusRT;
                delta = tmp.dVdS - ONE;
            }

            tmp.t1 = (ONE - tmp.u) * tmp.p / ONE / 2;
            tmp.t2 = (ONE - tmp.w) * tmp.q / ONE / 2;
            gamma = tmp.A * (tmp.t1 - ONE) / S * tmp.t1 / ONE - tmp.B * K / S * (tmp.t2 - ONE) / S * tmp.t2 / ONE;
        }
    }

}
