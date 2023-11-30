// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';

interface IDToken is IERC721 {

    function ownerOf(uint256) external view returns (address);

    function totalMinted() external view returns (uint160);

    function mint(address owner) external returns (uint256 tokenId);

    function burn(uint256 tokenId) external;

}
