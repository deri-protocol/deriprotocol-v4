// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../utils/IAdmin.sol';
import '../utils/IImplementation.sol';
import '../utils/IVerifier.sol';

interface IOracle is IAdmin, IImplementation, IVerifier {

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

    function getOracleId(string memory symbol) external pure returns (bytes32);

    function getState(bytes32 oracleId) external view returns (State memory s);

    function getValue(bytes32 oracleId) external view returns (int256);

    function getValueCurrentBlock(bytes32 oracleId) external view returns (int256);

    function setOffchainOracle(string memory symbol, uint256 delayAllowance) external;

    function setChainlinkOracle(string memory symbol, address feed) external;

    function updateOffchainValue(Signature memory sig) external;

    function updateOffchainValues(Signature[] memory sigs) external;

}
