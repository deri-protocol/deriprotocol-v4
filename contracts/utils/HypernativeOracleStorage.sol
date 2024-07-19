// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './Admin.sol';
import './Implementation.sol';

abstract contract HypernativeOracleStorage is Admin, Implementation {

    mapping (uint256 => address) internal _operators;

    mapping (uint256 => bool) internal _switches;

}
