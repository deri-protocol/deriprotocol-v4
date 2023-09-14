// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './Bytes32.sol';

library Bytes32Map {

    function getBytes32(mapping(uint8 => bytes32) storage store, uint8 idx) internal view returns (bytes32) {
        return store[idx];
    }

    function getAddress(mapping(uint8 => bytes32) storage store, uint8 idx) internal view returns (address) {
        return Bytes32.toAddress(store[idx]);
    }

    function getUint(mapping(uint8 => bytes32) storage store, uint8 idx) internal view returns (uint256) {
        return Bytes32.toUint(store[idx]);
    }

    function getInt(mapping(uint8 => bytes32) storage store, uint8 idx) internal view returns (int256) {
        return Bytes32.toInt(store[idx]);
    }

    function getBool(mapping(uint8 => bytes32) storage store, uint8 idx) internal view returns (bool) {
        return Bytes32.toBool(store[idx]);
    }

    function getString(mapping(uint8 => bytes32) storage store, uint8 idx) internal view returns (string memory) {
        return Bytes32.toString(store[idx]);
    }


    function set(mapping(uint8 => bytes32) storage store, uint8 idx, bytes32 value) internal {
        store[idx] = value;
    }

    function set(mapping(uint8 => bytes32) storage store, uint8 idx, address value) internal {
        store[idx] = Bytes32.toBytes32(value);
    }

    function set(mapping(uint8 => bytes32) storage store, uint8 idx, uint256 value) internal {
        store[idx] = Bytes32.toBytes32(value);
    }

    function set(mapping(uint8 => bytes32) storage store, uint8 idx, int256 value) internal {
        store[idx] = Bytes32.toBytes32(value);
    }

    function set(mapping(uint8 => bytes32) storage store, uint8 idx, bool value) internal {
        store[idx] = Bytes32.toBytes32(value);
    }

    function set(mapping(uint8 => bytes32) storage store, uint8 idx, string memory value) internal {
        store[idx] = Bytes32.toBytes32(value);
    }

    function del(mapping(uint8 => bytes32) storage store, uint8 idx) internal {
        delete store[idx];
    }

}
