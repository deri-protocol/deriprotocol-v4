// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../utils/Admin.sol';
import '../utils/Implementation.sol';

abstract contract OracleStorage is Admin, Implementation {

    // oracleId => baseOracle
    mapping (bytes32 => address) public baseOracles;

}
