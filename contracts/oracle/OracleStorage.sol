// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../utils/Admin.sol';
import '../utils/Implementation.sol';
import '../utils/Verifier.sol';

abstract contract OracleStorage is Admin, Implementation, Verifier {

    // oracleId => stateId => value
    mapping(bytes32 => mapping(uint8 => bytes32)) internal _states;

}
