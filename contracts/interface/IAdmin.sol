// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IAdmin {

    function admin() external view returns (address);

    function setAdmin(address newAdmin) external;

}
