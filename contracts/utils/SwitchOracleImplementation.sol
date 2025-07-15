// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './SwitchOracleStorage.sol';

contract SwitchOracleImplementation is SwitchOracleStorage {

    address public immutable gateway;

    constructor (address gateway_) {
        gateway = gateway_;
    }

    function enableGatewayTransferOut() external _onlyAdmin_ {
        gatewayTransferOutDisabled = false;
    }

    function disableGatewayTransferOut() external {
        require(msg.sender == gateway, 'Only Gateway');
        gatewayTransferOutDisabled = true;
    }

}
