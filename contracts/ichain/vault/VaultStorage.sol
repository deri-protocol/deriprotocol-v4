// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../../utils/Admin.sol';
import '../../utils/Implementation.sol';

abstract contract VaultStorage is Admin, Implementation {

    // dTokenId => stAmount
    // The 'stAmount' represents the stake or equity held by a 'dTokenId' within a vault
    // The portion 'stAmount / stTotalAmount' denotes the share of equity that a specific 'dTokenId' has within this vault
    mapping(uint256 => uint256) public stAmounts;

    uint256 public stTotalAmount;

    uint256 public tradersTotalAssetAmount;

}
