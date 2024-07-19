// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface ISwitchOracle {

    function getOperator(uint256 key) external view returns (address);

    function getSwitch(uint256 key) external view returns (bool);

    function getSwitchWithdrawDisabled() external view returns (bool);

    function setOperator(uint256 key, address operator) external;

    function resetSwitch(uint256 key) external;

    function setSwitchWithdrawDisabled() external;

}
