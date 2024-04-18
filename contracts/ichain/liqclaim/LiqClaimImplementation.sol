// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../token/IDToken.sol';
import './LiqClaimStorage.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../../library/ETHAndERC20.sol';

contract LiqClaimImplementation is LiqClaimStorage {

    using ETHAndERC20 for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    event Deposit(
        address owner,
        address bToken,
        uint256 amount
    );

    event Claim(
        address owner,
        address bToken,
        uint256 amount
    );

    // should transfer token before calling deposit
    function deposit(address owner, address bToken, uint256 amount) external {
        uint256 preBalance = _totalAmounts[bToken];
        uint256 curBalance =  bToken.balanceOfThis();
        require(curBalance >= preBalance + amount, 'Wrong amount');

        if (preBalance == 0) {
            _claimableTokens[owner].add(bToken);
        }
        _claimableAmounts[owner][bToken] += amount;
        _totalAmounts[bToken] += amount;

        emit Deposit(owner, bToken, amount);
    }

    function redeem() external {
        uint256 length = _claimableTokens[msg.sender].length();
        for (uint256 i = length; i > 0; i--) {
            address bToken = _claimableTokens[msg.sender].at(i-1);
            uint256 amount = _claimableAmounts[msg.sender][bToken];
            bToken.transferOut(msg.sender, amount);
            _claimableTokens[msg.sender].remove(bToken);
            delete _claimableAmounts[msg.sender][bToken];
            emit Claim(msg.sender, bToken, amount);
        }
    }

}
