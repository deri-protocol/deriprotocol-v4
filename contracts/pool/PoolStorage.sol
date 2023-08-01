// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../utils/Admin.sol';
import '../utils/ReentryLock.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

abstract contract PoolStorage is Admin, ReentryLock {

    event NewImplementation(address newImplementation);

    address public implementation;

    // stateId => value
    mapping(uint8 => bytes32) internal _states;

    // stTokenId => stateId => value
    mapping(bytes32 => mapping(uint8 => bytes32)) internal _stTokenStates;

    // lTokenId => stateId => value
    mapping(uint256 => mapping(uint8 => bytes32)) internal _lpStates;

    // pTokenId => stateId => value
    mapping(uint256 => mapping(uint8 => bytes32)) internal _tdStates;

}
