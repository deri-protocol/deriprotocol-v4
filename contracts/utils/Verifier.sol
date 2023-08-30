// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './Admin.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';

abstract contract Verifier is Admin {

    event AddVerifier(address verifier);
    event DelVerifier(address verifier);

    error InvalidSignature();

    mapping(address => bool) internal _verifiers;

    function addVerifier(address verifier) external _onlyAdmin_ {
        _verifiers[verifier] = true;
        emit AddVerifier(verifier);
    }

    function delVerifier(address verifier) external _onlyAdmin_ {
        _verifiers[verifier] = false;
        emit DelVerifier(verifier);
    }

    function _verifyMessage(bytes32 message, bytes memory signature) internal view {
        bytes32 hash = ECDSA.toEthSignedMessageHash(message);
        address signer = ECDSA.recover(hash, signature);
        if (!_verifiers[signer]) {
            revert InvalidSignature();
        }
    }

    function _verifyMessage(bytes32 message, uint8 v, bytes32 r, bytes32 s) internal view {
        bytes32 hash = ECDSA.toEthSignedMessageHash(message);
        address signer = ECDSA.recover(hash, v, r, s);
        if (!_verifiers[signer]) {
            revert InvalidSignature();
        }
    }

}
