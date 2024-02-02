// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './IOracle.sol';
import './OracleStorage.sol';

contract OracleImplementation is OracleStorage {

    function setBaseOracle(string memory symbol, address baseOracle) external _onlyAdmin_ {
        bytes32 oracleId = keccak256(abi.encodePacked(symbol));
        baseOracles[oracleId] = baseOracle;
    }

    // @notice Get oracle value without any checking
    function getValue(bytes32 oracleId) public view returns (int256) {
        return IOracle(baseOracles[oracleId]).getValue(oracleId);
    }

    // @notice Get oracle value of current block
    // @dev When source is offchain, value must be updated in current block, otherwise revert
    function getValueCurrentBlock(bytes32 oracleId) public view returns (int256) {
        return IOracle(baseOracles[oracleId]).getValueCurrentBlock(oracleId);
    }

    function updateOffchainValue(IOracle.Signature memory s) public {
        IOracle(baseOracles[s.oracleId]).updateOffchainValue(s);
    }

    function updateOffchainValues(IOracle.Signature[] memory ss) public {
        for (uint256 i = 0; i < ss.length; i++) {
            IOracle(baseOracles[ss[i].oracleId]).updateOffchainValue(ss[i]);
        }
    }

}
