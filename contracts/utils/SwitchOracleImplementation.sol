// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './SwitchOracleStorage.sol';

contract SwitchOracleImplementation is SwitchOracleStorage {

    address public operator;
    bool public state;

    function setOperator(address operator_) external _onlyAdmin_ {
        operator = operator_;
    }

    function resetState() external _onlyAdmin_ {
        state = false;
    }

    function setState() external {
        require(msg.sender == operator, 'not operator');
        state = true;
    }

}
