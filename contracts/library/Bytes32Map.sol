// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

library Bytes32Map {

    error StringExceeds31Bytes(string value);

    function getBytes32(mapping(uint8 => bytes32) storage store, uint8 idx) internal view returns (bytes32) {
        return store[idx];
    }

    function getAddress(mapping(uint8 => bytes32) storage store, uint8 idx) internal view returns (address) {
        return address(uint160(uint256(store[idx])));
    }

    function getUint(mapping(uint8 => bytes32) storage store, uint8 idx) internal view returns (uint256) {
        return uint256(store[idx]);
    }

    function getInt(mapping(uint8 => bytes32) storage store, uint8 idx) internal view returns (int256) {
        return int256(uint256(store[idx]));
    }

    function getBool(mapping(uint8 => bytes32) storage store, uint8 idx) internal view returns (bool) {
        return store[idx] != bytes32(0);
    }

    function getString(mapping(uint8 => bytes32) storage store, uint8 idx) internal view returns (string memory) {
        return bytes32ToString(store[idx]);
    }


    function set(mapping(uint8 => bytes32) storage store, uint8 idx, bytes32 value) internal {
        store[idx] = value;
    }

    function set(mapping(uint8 => bytes32) storage store, uint8 idx, address value) internal {
        store[idx] = bytes32(uint256(uint160(value)));
    }

    function set(mapping(uint8 => bytes32) storage store, uint8 idx, uint256 value) internal {
        store[idx] = bytes32(value);
    }

    function set(mapping(uint8 => bytes32) storage store, uint8 idx, int256 value) internal {
        store[idx] = bytes32(uint256(value));
    }

    function set(mapping(uint8 => bytes32) storage store, uint8 idx, bool value) internal {
        store[idx] = bytes32(uint256(value ? 1 : 0));
    }

    function set(mapping(uint8 => bytes32) storage store, uint8 idx, string memory value) internal {
        store[idx] = stringToBytes32(value);
    }

    function del(mapping(uint8 => bytes32) storage store, uint8 idx) internal {
        delete store[idx];
    }

    function stringToBytes32(string memory value) internal pure returns (bytes32) {
        if (bytes(value).length > 31) {
            revert StringExceeds31Bytes(value);
        }
        bytes32 res;
        assembly {
            res := mload(add(value, 0x20))
        }
        return res;
    }

    function bytes32ToString(bytes32 value) internal pure returns (string memory) {
        bytes memory bytesArray = new bytes(32);
        for (uint256 i = 0; i < 32; i++) {
            if (value[i] == 0) {
                assembly {
                    mstore(bytesArray, i)
                }
                break;
            } else {
                bytesArray[i] = value[i];
            }
        }
        return string(bytesArray);
    }

}
