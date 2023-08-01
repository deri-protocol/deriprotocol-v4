// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '@openzeppelin/contracts/token/ERC721/ERC721.sol';

contract DToken is ERC721 {

    error ChainIdOverflow();
    error OnlyVault();

    // We use the higher 96 bits to store the chainId
    // thus trade engine on L3 can easily distinguish tokenIds from various interface chains
    // support chainId up to 2^96 = 79228162514264337593543950336
    uint256 immutable BASE_ID;

    address public immutable vault;

    uint128 public totalMinted;

    constructor (string memory name_, string memory symbol_, address vault_) ERC721(name_, symbol_) {
        vault = vault_;
        if (block.chainid > type(uint96).max) {
            revert ChainIdOverflow();
        }
        BASE_ID = uint256(block.chainid) << 160;
    }

    function mint(address owner) external returns (uint256 tokenId) {
        if (msg.sender != vault) {
            revert OnlyVault();
        }
        tokenId = BASE_ID + uint256(++totalMinted);
        _mint(owner, tokenId);
    }

}
