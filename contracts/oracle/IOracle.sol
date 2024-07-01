// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../utils/IAdmin.sol';
import '../utils/IImplementation.sol';

interface IOracle is IAdmin, IImplementation {

    struct Signature {
        bytes32 oracleId;
        uint256 timestamp;
        int256  value;
        uint8   v;
        bytes32 r;
        bytes32 s;
    }

    function getValue(bytes32 oracleId) external view returns (int256);

    function getValueCurrentBlock(bytes32 oracleId) external returns (int256);

    function updateOffchainValue(Signature memory s) external;

    function updateOffchainValues(Signature[] memory ss) external;

}
