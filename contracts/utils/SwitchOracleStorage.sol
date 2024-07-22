// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './Admin.sol';
import './Implementation.sol';

abstract contract SwitchOracleStorage is Admin, Implementation {}
