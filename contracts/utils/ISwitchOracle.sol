// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface ISwitchOracle {

    function operator() external view returns (address);

    function state() external view returns (bool);

    function setOperator(address operator_) external;

    function resetState() external;

    function setState() external;

}
