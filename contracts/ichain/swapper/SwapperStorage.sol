// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../../utils/Admin.sol';
import '../../utils/Implementation.sol';

abstract contract SwapperStorage is Admin, Implementation {

    // tokenBX => base swapper, address(1) is reserved for ETH
    mapping(address => address) public baseSwappers;

    // tokenBX => oracleId
    mapping(address => bytes32) public oracleIds;

    // tokenBX => maxSlippageRatio
    mapping(address => uint256) public maxSlippageRatios;

}
