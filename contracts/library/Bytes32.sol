// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

library Bytes32 {

    error StringExceeds31Bytes(string value);

    function toUint(bytes32 value) internal pure returns (uint256) {
        return uint256(value);
    }

    function toInt(bytes32 value) internal pure returns (int256) {
        return int256(uint256(value));
    }

    function toAddress(bytes32 value) internal pure returns (address) {
        return address(uint160(uint256(value)));
    }

    function toBool(bytes32 value) internal pure returns (bool) {
        return value != bytes32(0);
    }

    /**
     * @notice Convert a bytes32 value to a string.
     * @dev This function takes an input bytes32 'value' and converts it into a string.
     *      It dynamically determines the length of the string based on non-null characters in 'value'.
     * @param value The input bytes32 value to be converted.
     * @return The string representation of the input bytes32.
     */
    function toString(bytes32 value) internal pure returns (string memory) {
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

    function toBytes32(uint256 value) internal pure returns (bytes32) {
        return bytes32(value);
    }

    function toBytes32(int256 value) internal pure returns (bytes32) {
        return bytes32(uint256(value));
    }

    function toBytes32(address value) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(value)));
    }

    function toBytes32(bool value) internal pure returns (bytes32) {
        return bytes32(uint256(value ? 1 : 0));
    }

    /**
     * @notice Convert a string to a bytes32 value.
     * @dev This function takes an input string 'value' and converts it into a bytes32 value.
     *      It enforces a length constraint of 31 characters or less to ensure it fits within a bytes32.
     *      The function uses inline assembly to efficiently copy the string data into the bytes32.
     * @param value The input string to be converted.
     * @return The bytes32 representation of the input string.
     */
    function toBytes32(string memory value) internal pure returns (bytes32) {
        if (bytes(value).length > 31) {
            revert StringExceeds31Bytes(value);
        }
        bytes32 res;
        assembly {
            res := mload(add(value, 0x20))
        }
        return res;
    }

}
