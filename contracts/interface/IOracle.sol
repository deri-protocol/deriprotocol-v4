// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IOracle {

    struct State {
        string  symbol;
        uint256 source;
        uint256 delayAllowance;
        uint256 blockNumber;
        uint256 timestamp;
        int256  value;
        address chainlinkFeed;
    }

    struct Signature {
        bytes32 oracleId;
        uint256 timestamp;
        int256  value;
        uint8   v;
        bytes32 r;
        bytes32 s;
    }

    function getValue(bytes32 oracleId) external view returns (int256);

    function updateOffchainValue(Signature memory sig) external returns (bool);

}
