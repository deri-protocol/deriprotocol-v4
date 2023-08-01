// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './OracleStorage.sol';

contract Oracle is OracleStorage {

    function setImplementation(address newImplementation) external _onlyAdmin_ {
        implementation = newImplementation;
        emit NewImplementation(newImplementation);
    }

    function setSigner(address newSinger) external _onlyAdmin_ {
        signer = newSinger;
        emit NewSigner(newSinger);
    }

    fallback() external payable {
        address imp = implementation;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), imp, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}

}
