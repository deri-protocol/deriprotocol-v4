// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

library ETHAndERC20 {

    using SafeERC20 for IERC20;

    error SendEthFail();
    error WrongTokenInAmount();
    error WrongTokenOutAmount();

    // Address 0x0000000000000000000000000000000000000001 represents ETH

    function decimals(address token) internal view returns (uint8) {
        return token == address(1) ? 18 : IERC20Metadata(token).decimals();
    }

    function balanceOfThis(address token) internal view returns (uint256) {
        return token == address(1)
            ? address(this).balance
            : IERC20(token).balanceOf(address(this));
    }

    function approveMax(address token, address spender) internal {
        if (token != address(1)) {
            uint256 allowance = IERC20(token).allowance(address(this), spender);
            if (allowance != type(uint256).max) {
                if (allowance != 0) {
                    IERC20(token).safeApprove(spender, 0);
                }
                IERC20(token).safeApprove(spender, type(uint256).max);
            }
        }
    }

    function unapprove(address token, address spender) internal {
        if (token != address(1)) {
            uint256 allowance = IERC20(token).allowance(address(this), spender);
            if (allowance != 0) {
                IERC20(token).safeApprove(spender, 0);
            }
        }
    }

    function transferIn(address token, address from, uint256 amount) internal {
        if (token == address(1)) {
            if (amount != msg.value) {
                revert WrongTokenInAmount();
            }
        } else {
            uint256 balance1 = balanceOfThis(token);
            IERC20(token).safeTransferFrom(from, address(this), amount);
            uint256 balance2 = balanceOfThis(token);
            if (balance2 != balance1 + amount) {
                revert WrongTokenInAmount();
            }
        }
    }

    function transferOut(address token, address to, uint256 amount) internal {
        uint256 balance1 = balanceOfThis(token);
        if (token == address(1)) {
            (bool success, ) = payable(to).call{value: amount}('');
            if (!success) {
                revert SendEthFail();
            }
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
        uint256 balance2 = balanceOfThis(token);
        if (balance1 != balance2 + amount) {
            revert WrongTokenOutAmount();
        }
    }

}
