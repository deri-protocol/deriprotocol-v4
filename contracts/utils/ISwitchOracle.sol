// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface ISwitchOracle {

    function operator() external view returns (address);

    function transferOutFreezed(address gateway) external view returns (bool);

    function setOperator(address operator_) external;

    function freezeTransferOut() external;

    function freezeTransferOut(address gateway) external;

    function unfreezeTransferOut(address gateway) external;

}
