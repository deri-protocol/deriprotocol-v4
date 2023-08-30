// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';

library Verification {

    error InvalidSignature();

    function verifyBytes(bytes memory data, bytes memory sig, address signatory) internal pure {
        bytes32 hash = ECDSA.toEthSignedMessageHash(keccak256(data));
        if (ECDSA.recover(hash, sig) != signatory) {
            revert InvalidSignature();
        }
    }

}
