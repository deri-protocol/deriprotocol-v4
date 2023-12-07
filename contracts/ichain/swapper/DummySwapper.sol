// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

// Dummy swapper without any swapping functionalities
// Just used for gateways with only tokenB0 supported
contract DummySwapper {

    function isSupportedToken(address bToken) external pure returns (bool) {
        bToken;
        return true;
    }

}
