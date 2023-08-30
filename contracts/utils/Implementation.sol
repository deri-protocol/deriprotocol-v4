// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './Admin.sol';

abstract contract Implementation is Admin {

    event NewImplementation(address newImplementation);

    address public implementation;

    function setImplementation(address newImplementation) external _onlyAdmin_ {
        implementation = newImplementation;
        emit NewImplementation(newImplementation);
    }

}
