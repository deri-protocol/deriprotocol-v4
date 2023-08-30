// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract IOU is ERC20 {

    error OnlyVault();

    address public immutable vault;

    modifier _onlyVault_() {
        if (msg.sender != vault) {
            revert OnlyVault();
        }
        _;
    }

    constructor (string memory name_, string memory symbol_, address vault_) ERC20(name_, symbol_) {
        vault = vault_;
    }

    function mint(address account, uint256 amount) external _onlyVault_ {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external _onlyVault_ {
        _burn(account, amount);
    }

}
