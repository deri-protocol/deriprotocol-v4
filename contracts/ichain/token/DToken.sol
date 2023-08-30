// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '@openzeppelin/contracts/token/ERC721/ERC721.sol';

contract DToken is ERC721 {

    error ChainIdOverflow();
    error OnlyVault();

    // We encode the dTokenId as follows to ensure every dTokenId
    // on all chains in every DToken contract is unique
    // 1. The highest 8 bits: Unique identifier to differentiate between different DToken contracts deployed on the same chain
    // 1. The next 88 bits: Reserved for the chainid, which is used to distinguish DToken contracts deployed on different chains
    // 3. The lowest 160 bits: Used to distinguish the individual dTokens minted within a specific contract
    // The highest 96 bits will be fixed at deployment, and stored in BASE_TOKENID
    uint256 public immutable BASE_TOKENID;

    // Only vault can mint/burn tokens
    address public immutable vault;

    // Total number of tokens minted, included those burned
    uint160 public totalMinted;

    modifier _onlyVault_() {
        if (msg.sender != vault) {
            revert OnlyVault();
        }
        _;
    }

    constructor (
        uint8 uniqueIdentifier,
        string memory name_,
        string memory symbol_,
        address vault_
    ) ERC721(name_, symbol_) {
        vault = vault_;
        if (block.chainid > type(uint88).max) {
            revert ChainIdOverflow();
        }
        BASE_TOKENID = (uint256(uniqueIdentifier) << 248) + (block.chainid << 160);
    }

    function mint(address owner) external _onlyVault_ returns (uint256 tokenId) {
        tokenId = BASE_TOKENID + uint256(++totalMinted);
        _safeMint(owner, tokenId);
    }

    function burn(uint256 tokenId) external _onlyVault_ {
        _burn(tokenId);
    }

}
