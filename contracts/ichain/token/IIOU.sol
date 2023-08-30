// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface IIOU is IERC20 {

    function vault() external view returns (address);

    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external;

}
