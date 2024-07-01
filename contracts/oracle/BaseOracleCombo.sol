// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './IOracle.sol';
import '../utils/Admin.sol';

contract BaseOracleCombo is Admin {

    int256 constant ONE = 1e18;

    struct SubOracle {
        bytes32 oracleId;
        address oracleAddress;
        bool reciprocal;
    }

    // oracleId => SubOracle[]
    mapping (bytes32 => SubOracle[]) public subOracles;

    function set(string memory symbol, SubOracle[] memory subs) external _onlyAdmin_ {
        bytes32 oracleId = keccak256(abi.encodePacked(symbol));

        delete subOracles[oracleId];
        for (uint256 i = 0; i < subs.length; i++) {
            subOracles[oracleId].push(subs[i]);
        }
    }

    function getValue(bytes32 oracleId) public view returns (int256) {
        SubOracle[] storage subs = subOracles[oracleId];
        require(subs.length > 0, 'No sub oracles');

        int256 value = ONE;
        for (uint256 i = 0; i < subs.length; i++) {
            int256 iValue = IOracle(subs[i].oracleAddress).getValue(subs[i].oracleId);
            if (subs[i].reciprocal) {
                value = value * ONE / iValue;
            } else {
                value = value * iValue / ONE;
            }
        }

        return value;
    }

    function getValueCurrentBlock(bytes32 oracleId) public returns (int256) {
        SubOracle[] storage subs = subOracles[oracleId];
        require(subs.length > 0, 'No sub oracles');

        int256 value = ONE;
        for (uint256 i = 0; i < subs.length; i++) {
            int256 iValue = IOracle(subs[i].oracleAddress).getValueCurrentBlock(subs[i].oracleId);
            if (subs[i].reciprocal) {
                value = value * ONE / iValue;
            } else {
                value = value * iValue / ONE;
            }
        }

        return value;
    }

}
