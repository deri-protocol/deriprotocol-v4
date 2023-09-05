// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract IOU is ERC20 {

    error OnlyGateway();

    address public immutable gateway;

    modifier _onlyGateway_() {
        if (msg.sender != gateway) {
            revert OnlyGateway();
        }
        _;
    }

    constructor (string memory name_, string memory symbol_, address gateway_) ERC20(name_, symbol_) {
        gateway = gateway_;
    }

    function mint(address account, uint256 amount) external _onlyGateway_ {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external _onlyGateway_ {
        _burn(account, amount);
    }

}
