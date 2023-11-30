// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './IAdmin.sol';

contract Deployer2 {

    event Deployed(address addr, uint256 salt);

    function deploy2(bytes memory code, uint256 salt) external {
        address addr;
        assembly {
            addr := create2(0, add(code, 0x20), mload(code), salt)
            if iszero(extcodesize(addr)) {
                revert (0, 0)
            }
        }

        (bool success, bytes memory data) = addr.staticcall(
            abi.encodeWithSelector(IAdmin.admin.selector)
        );
        if (success && abi.decode(data, (address)) == address(this)) {
            IAdmin(addr).setAdmin(msg.sender);
        }

        emit Deployed(addr, salt);
    }

}
