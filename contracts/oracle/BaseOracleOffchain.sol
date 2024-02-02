// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './IOracle.sol';
import '../utils/Admin.sol';
import '../utils/Verifier.sol';

contract BaseOracleOffchain is Admin, Verifier {

    event NewOffchainValue(bytes32 oracleId, uint256 timestamp, int256 value);

    struct Info {
        uint256 delayAllowance;
        uint256 lastBlockNumber;
        uint256 lastTimestamp;
        int256  value;
    }

    // oracleId => Info
    mapping (bytes32 => Info) public infos;

    function set(string memory symbol, uint256 delayAllowance, int256 initValue) external _onlyAdmin_ {
        bytes32 oracleId = keccak256(abi.encodePacked(symbol));
        infos[oracleId].delayAllowance = delayAllowance;
        infos[oracleId].value = initValue;
    }

    // @notice Get oracle value without any checking
    function getValue(bytes32 oracleId) public view returns (int256) {
        return infos[oracleId].value;
    }

    // @notice Get oracle value of current block
    // @dev When source is offchain, value must be updated in current block, otherwise revert
    function getValueCurrentBlock(bytes32 oracleId) public view returns (int256) {
        uint256 blockNumber = infos[oracleId].lastBlockNumber;
        require(blockNumber == block.number, 'Not current block');
        return infos[oracleId].value;
    }

    function updateOffchainValue(IOracle.Signature memory s) external {
        bytes32 message = keccak256(abi.encodePacked(s.oracleId, s.timestamp, s.value));
        _verifyMessage(message, s.v, s.r, s.s);

        Info storage info = infos[s.oracleId];
        if (
            block.number > info.lastBlockNumber && // Can only be updated once in same block
            s.timestamp > info.lastTimestamp && // Update value must be newer
            block.timestamp < s.timestamp + info.delayAllowance // New value must not expire
        ) {
            info.lastBlockNumber = block.number;
            info.lastTimestamp = s.timestamp;
            info.value = s.value;
            emit NewOffchainValue(s.oracleId, s.timestamp, s.value);
        }
    }

}
