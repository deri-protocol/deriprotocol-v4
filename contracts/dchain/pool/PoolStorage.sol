// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../../utils/Admin.sol';
import '../../utils/Implementation.sol';
import '../../utils/ReentryLock.sol';

abstract contract PoolStorage is Admin, Implementation, ReentryLock {

    // stateId => value
    mapping(uint8 => bytes32) internal _states;

    // chainId => stateId => value
    mapping(uint88 => mapping(uint8 => bytes32)) internal _iStates;

    // dTokenId => stateId => value
    mapping(uint256 => mapping(uint8 => bytes32)) internal _dStates;

}
