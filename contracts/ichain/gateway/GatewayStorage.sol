// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../../utils/Admin.sol';
import '../../utils/Implementation.sol';
import '../../utils/ReentryLock.sol';

abstract contract GatewayStorage is Admin, Implementation, ReentryLock {

    mapping(uint8 => bytes32) internal _gatewayStates;

    mapping(address => mapping(uint8 => bytes32)) internal _bTokenStates;

    mapping(uint256 => mapping(uint8 => bytes32)) internal _dTokenStates;

}
