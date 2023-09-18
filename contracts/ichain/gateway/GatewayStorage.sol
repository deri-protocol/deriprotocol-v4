// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../../utils/Admin.sol';
import '../../utils/Implementation.sol';
import '../../utils/ReentryLock.sol';

abstract contract GatewayStorage is Admin, Implementation, ReentryLock {

    // stateId => value
    mapping(uint8 => bytes32) internal _gatewayStates;

    // bToken => stateId => value
    mapping(address => mapping(uint8 => bytes32)) internal _bTokenStates;

    // dTokenId => stateId => value
    mapping(uint256 => mapping(uint8 => bytes32)) internal _dTokenStates;

    // actionId => executionFee
    mapping(uint256 => uint256) internal _executionFees;

}
