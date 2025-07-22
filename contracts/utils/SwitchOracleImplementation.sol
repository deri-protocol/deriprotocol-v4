// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './SwitchOracleStorage.sol';

contract SwitchOracleImplementation is SwitchOracleStorage {

    event FreezeTransferOut(address gateway);
    event UnfreezeTransferOut(address gateway);

    function setOperator(address operator_) external _onlyAdmin_ {
        operator = operator_;
    }

    function freezeTransferOut() external {
        transferOutFreezed[msg.sender] = true;
        emit FreezeTransferOut(msg.sender);
    }

    function freezeTransferOut(address gateway) external {
        require(msg.sender == operator, 'Only operator');
        transferOutFreezed[gateway] = true;
        emit FreezeTransferOut(gateway);
    }

    function unfreezeTransferOut(address gateway) external _onlyAdmin_ {
        transferOutFreezed[gateway] = false;
        emit UnfreezeTransferOut(gateway);
    }

}
