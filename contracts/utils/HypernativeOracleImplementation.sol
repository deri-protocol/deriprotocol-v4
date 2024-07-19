// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './HypernativeOracleStorage.sol';

contract HypernativeOracleImplementation is HypernativeOracleStorage {

    event SetOperator(uint256 key, address operator);
    event SetSwitch(uint256 key, bool state);

    uint256 constant keyWithdrawDisabled = 101;

    //================================================================================
    // Views
    //================================================================================

    function getOperator(uint256 key) external view returns (address) {
        return _operators[key];
    }

    function getSwitch(uint256 key) external view returns (bool) {
        return _switches[key];
    }

    function getSwitchWithdrawDisabled() external view returns (bool) {
        return _switches[keyWithdrawDisabled];
    }

    //================================================================================
    // Admin
    //================================================================================

    function setOperator(uint256 key, address operator) external _onlyAdmin_ {
        _operators[key] = operator;
        emit SetOperator(key, operator);
    }

    function resetSwitch(uint256 key) external _onlyAdmin_ {
        _switches[key] = false;
        emit SetSwitch(key, false);
    }

    //================================================================================
    // Operator
    //================================================================================

    function setSwitchWithdrawDisabled() external {
        require(_operators[keyWithdrawDisabled] == msg.sender, 'not operator');
        _switches[keyWithdrawDisabled] = true;
        emit SetSwitch(keyWithdrawDisabled, true);
    }

}
