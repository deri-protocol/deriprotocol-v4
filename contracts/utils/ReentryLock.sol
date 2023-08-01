// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

abstract contract ReentryLock {

    error Reentry();

    bool internal _mutex;

    modifier _reentryLock_() {
        if (_mutex) {
            revert Reentry();
        }
        _mutex = true;
        _;
        _mutex = false;
    }

}
