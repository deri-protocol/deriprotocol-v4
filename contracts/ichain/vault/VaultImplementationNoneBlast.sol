// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './VaultImplementationNone.sol';

contract VaultImplementationNoneBlast is VaultImplementationNone {

    constructor (address gateway_, address asset_) VaultImplementationNone(gateway_, asset_) {}

    function configureBlastPointsOperator(address blastPoints_, address operator_) external _onlyAdmin_ {
        IBlastPoints(blastPoints_).configurePointsOperator(operator_);
    }

}

interface IBlastPoints {
    function configurePointsOperator(address operator) external;
    function configurePointsOperatorOnBehalf(address contractAddress, address operator) external;
}
