// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './SwitchOracleStorage.sol';

contract SwitchOracleImplementation is SwitchOracleStorage {

    event FreezeGatewayTransferOut();
    event UnfreezeGatewayTransferOut();

    address public immutable gateway;

    constructor (address gateway_) {
        gateway = gateway_;
    }

    function setOperator(address operator_) external _onlyAdmin_ {
        operator = operator_;
    }

    function unfreezeGatewayTransferOut() external _onlyAdmin_ {
        gatewayTransferOutFreezed = false;
        emit UnfreezeGatewayTransferOut();
    }

    function freezeGatewayTransferOut() external {
        require(msg.sender == gateway || msg.sender == operator, 'Only Gateway or operator');
        gatewayTransferOutFreezed = true;
        emit FreezeGatewayTransferOut();
    }

}
