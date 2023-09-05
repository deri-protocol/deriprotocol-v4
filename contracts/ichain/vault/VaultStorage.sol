// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../../utils/Admin.sol';
import '../../utils/Implementation.sol';

abstract contract VaultStorage is Admin, Implementation {

    // dTokenId => stAmount
    mapping(uint256 => uint256) public stAmounts;

    uint256 public stTotalAmount;

}
