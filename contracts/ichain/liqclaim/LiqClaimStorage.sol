// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../../utils/Admin.sol';
import '../../utils/Implementation.sol';

abstract contract LiqClaimStorage is Admin, Implementation {

    mapping (address => EnumerableSet.AddressSet) internal _claimableTokens;

    mapping (address => mapping (address => uint256)) internal _claimableAmounts;

    mapping (address => uint256) internal _totalAmounts;

}
