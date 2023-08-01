// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../utils/Admin.sol';

abstract contract OracleStorage is Admin {

    event NewImplementation(address newImplementation);

    event NewSigner(address newSinger);

    address public implementation;

    address public signer;

    // oracleId => stateId => value
    mapping(bytes32 => mapping(uint8 => bytes32)) internal _states;

}
