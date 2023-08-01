// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../utils/Admin.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

abstract contract SymbolManagerStorage is Admin {

    event NewImplementation(address newImplementation);

    address public implementation;

    EnumerableSet.Bytes32Set internal _symbolIds;

    // symbolId => stateId => value
    mapping(bytes32 => mapping(uint8 => bytes32)) internal _states;

    // symbolId => pTokenIds hold position
    mapping(bytes32 => EnumerableSet.UintSet) internal _pTokenIds;

    // pTokenId => symbolIds with position
    mapping(uint256 => EnumerableSet.Bytes32Set) internal _tdSymbolIds;

    // symbolId => pTokenId => positionId => value
    mapping(bytes32 => mapping(uint256 => mapping(uint8 => bytes32))) internal _positions;

    int256 public initialMarginRequired;

}
