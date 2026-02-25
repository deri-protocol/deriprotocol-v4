// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './ILiqClaim.sol';
import '../token/IDToken.sol';
import './LiqClaimStorage.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../../library/ETHAndERC20.sol';

contract LiqClaimImplementation is LiqClaimStorage {

    using ETHAndERC20 for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    event RegisterDeposit(
        address owner,
        address bToken,
        uint256 amount
    );

    event Redeem(
        address owner,
        address bToken,
        uint256 amount
    );

    function getClaimables(address owner) external view returns (ILiqClaim.Claimable[] memory) {
        uint256 length = _claimableTokens[owner].length();
        ILiqClaim.Claimable[] memory res = new ILiqClaim.Claimable[](length);
        for (uint256 i = 0; i < length; i++) {
            address bToken = _claimableTokens[owner].at(i);
            uint256 amount = _claimableAmounts[owner][bToken];
            res[i].bToken = bToken;
            res[i].amount = amount;
        }
        return res;
    }

    function getTotalAmount(address bToken) external view returns (uint256) {
        return _totalAmounts[bToken];
    }

    // should transfer token before calling registerDeposit
    // The absence of access control is by design ¡ª any caller can register a deposit, but the token transfer
    // must precede this call, ensuring the balance check enforces correctness
    function registerDeposit(address owner, address bToken, uint256 amount) external {
        if (amount > 0) {
            require(
                bToken.balanceOfThis() >= _totalAmounts[bToken] + amount,
                'Wrong amount'
            );

            if (_claimableAmounts[owner][bToken] == 0) {
                _claimableTokens[owner].add(bToken);
            }
            _claimableAmounts[owner][bToken] += amount;
            _totalAmounts[bToken] += amount;

            emit RegisterDeposit(owner, bToken, amount);
        }
    }

    function redeem() external {
        uint256 length = _claimableTokens[msg.sender].length();
        for (uint256 i = length; i > 0; i--) {
            address bToken = _claimableTokens[msg.sender].at(i-1);
            uint256 amount = _claimableAmounts[msg.sender][bToken];
            _claimableTokens[msg.sender].remove(bToken);
            _claimableAmounts[msg.sender][bToken] = 0;
            _totalAmounts[bToken] -= amount;
            bToken.transferOut(msg.sender, amount);
            emit Redeem(msg.sender, bToken, amount);
        }
    }

}
