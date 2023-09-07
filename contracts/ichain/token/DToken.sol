// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '@openzeppelin/contracts/token/ERC721/ERC721.sol';

/**
 * @title DToken Contract
 * @dev An ERC721 token contract designed to represent both Liquidity Providers (Lp) and Traders.
 *      This contract allows for the creation and management of unique tokens representing ownership or
 *      participation in various activities within the ecosystem.
 */
contract DToken is ERC721 {

    error ChainIdOverflow();
    error OnlyGateway();

    // Encoding of dTokenId
    // To ensure uniqueness across all DToken contracts on different chains, we encode the dTokenId as follows:
    // 1. The highest 8 bits: A unique identifier distinguishing between different DToken contracts deployed on the same chain.
    // 2. The next 88 bits: Reserved for the chainId, differentiating DToken contracts deployed on various chains.
    // 3. The lowest 160 bits: Used to distinguish individual dTokens minted within a specific contract.
    // The highest 96 bits remain fixed at deployment and are stored in BASE_TOKENID.
    uint256 public immutable BASE_TOKENID;

    // Only gateway can mint/burn tokens
    address public immutable gateway;

    // Total number of tokens minted, included those burned
    uint160 public totalMinted;

    modifier _onlyGateway_() {
        if (msg.sender != gateway) {
            revert OnlyGateway();
        }
        _;
    }

    constructor (
        uint8 uniqueIdentifier,
        string memory name_,
        string memory symbol_,
        address gateway_
    ) ERC721(name_, symbol_) {
        gateway = gateway_;
        if (block.chainid > type(uint88).max) {
            revert ChainIdOverflow();
        }
        BASE_TOKENID = (uint256(uniqueIdentifier) << 248) + (block.chainid << 160);
    }

    function mint(address owner) external _onlyGateway_ returns (uint256 tokenId) {
        tokenId = BASE_TOKENID + uint256(++totalMinted);
        _safeMint(owner, tokenId);
    }

    function burn(uint256 tokenId) external _onlyGateway_ {
        _burn(tokenId);
    }

}
