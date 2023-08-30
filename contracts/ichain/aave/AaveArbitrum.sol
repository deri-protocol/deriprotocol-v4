// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '@aave/core-v3/contracts/interfaces/IPool.sol';
import '@aave/core-v3/contracts/misc/interfaces/IWETH.sol';
import '@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '../../library/ETHAndERC20.sol';
import '../../library/SafeMath.sol';

library AaveArbitrum {

    using SafeERC20 for IERC20;
    using ETHAndERC20 for address;
    using SafeMath for uint256;

    error AaveNoMarket();
    error AaveWithdrawError();

    uint256 constant UONE = 1e18;

    address constant pool = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant rewardController = 0x929EC64c34a17401F460460D4B9390518E5B473e;

    function getStExRate(address bToken, uint256 stTotalAmount) external view returns (uint256 stExRate) {
        if (stTotalAmount != 0) {
            address market = getMarket(bToken);
            stExRate = market.balanceOfThis() * UONE / stTotalAmount;
        }
    }

    function enterMarket(address bToken) external {
        if (bToken == address(1)) {
            weth.approveMax(pool);
        } else {
            bToken.approveMax(pool);
        }
    }

    function exitMarket(address bToken) external {
        if (bToken == address(1)) {
            weth.unapprove(pool);
        } else {
            bToken.unapprove(pool);
        }
    }

    function deposit(address bToken, uint256 bAmount, uint256 stTotalAmount) external returns (uint256 stAmount) {
        if (bToken == address(1)) {
            IWETH(weth).deposit{value: bAmount}();
            IPool(pool).supply(weth, bAmount, address(this), 0);
        } else {
            IPool(pool).supply(bToken, bAmount, address(this), 0);
        }
        address market = getMarket(bToken);
        uint256 bAmountInCustodian = market.balanceOfThis();
        if (stTotalAmount == 0) {
            stAmount = bAmountInCustodian.rescale(bToken.decimals(), 18);
        } else {
            stAmount = bAmount * stTotalAmount / (bAmountInCustodian - bAmount);
        }
    }

    function redeem(address bToken, uint256 stAmount, uint256 stTotalAmount) external returns (uint256 bAmount) {
        address market = getMarket(bToken);
        uint256 bAmountInCustodian = market.balanceOfThis();
        bAmount = bAmountInCustodian * stAmount / stTotalAmount;
        uint256 withdrawnAmount;
        if (bToken == address(1)) {
            withdrawnAmount = IPool(pool).withdraw(weth, bAmount, address(this));
            IWETH(weth).withdraw(withdrawnAmount);
        } else {
            withdrawnAmount = IPool(pool).withdraw(bToken, bAmount, address(this));
        }
        if (withdrawnAmount != bAmount) {
            revert AaveWithdrawError();
        }
    }

    function redeemBToken(address bToken, uint256 bAmount, uint256 stTotalAmount) external returns (uint256 stAmount) {
        address market = getMarket(bToken);
        uint256 bAmountInCustodian = market.balanceOfThis();
        uint256 withdrawnAmount;
        if (bToken == address(1)) {
            withdrawnAmount = IPool(pool).withdraw(weth, bAmount, address(this));
            IWETH(weth).withdraw(withdrawnAmount);
        } else {
            withdrawnAmount = IPool(pool).withdraw(bToken, bAmount, address(this));
        }
        if (withdrawnAmount != bAmount) {
            revert AaveWithdrawError();
        }
        stAmount = bAmount * stTotalAmount / bAmountInCustodian;
    }

    function claimReward(address to) external {
        address[] memory assets = new address[](15);
        assets[0]  = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        assets[1]  = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
        assets[2]  = 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4;
        assets[3]  = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
        assets[4]  = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
        assets[5]  = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
        assets[6]  = 0xba5DdD1f9d7F570dc94a51479a000E3BCE967196;
        assets[7]  = 0xD22a58f79e9481D1a88e00c343885A588b34b68B;
        assets[8]  = 0x5979D7b546E38E414F7E9822514be443A4800529;
        assets[9]  = 0x3F56e0c36d275367b8C502090EDF38289b3dEa0d;
        assets[10] = 0xEC70Dcb4A1EFa46b8F2D97C310C9c4790ba5ffA8;
        assets[11] = 0x93b346b6BC2548dA6A1E7d98E9a421B42541425b;
        assets[12] = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        assets[13] = 0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F;
        assets[14] = 0x912CE59144191C1204E64559FE8253a0e49E6548;

        (address[] memory rewardsList, uint256[] memory claimedAmounts)
            = IRewardsController(rewardController).claimAllRewardsToSelf(assets);
        for (uint256 i = 0; i < rewardsList.length; i++) {
            if (claimedAmounts[i] != 0) {
                IERC20(rewardsList[i]).safeTransfer(to, claimedAmounts[i]);
            }
        }
    }

    function getMarket(address bToken) public pure returns (address) {
        if (bToken == 0x0000000000000000000000000000000000000001) return 0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8; // aArbWETH
        if (bToken == 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1) return 0x82E64f49Ed5EC1bC6e43DAD4FC8Af9bb3A2312EE; // aArbDAI
        if (bToken == 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4) return 0x191c10Aa4AF7C30e871E70C95dB0E4eb77237530; // aArbLINK
        if (bToken == 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8) return 0x625E7708f30cA75bfd92586e17077590C60eb4cD; // aArbUSDC
        if (bToken == 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f) return 0x078f358208685046a11C85e8ad32895DED33A249; // aArbWBTC
        if (bToken == 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9) return 0x6ab707Aca953eDAeFBc4fD23bA73294241490620; // aArbUSDT
        if (bToken == 0xba5DdD1f9d7F570dc94a51479a000E3BCE967196) return 0xf329e36C7bF6E5E86ce2150875a84Ce77f477375; // aArbAAVE
        if (bToken == 0xD22a58f79e9481D1a88e00c343885A588b34b68B) return 0x6d80113e533a2C0fe82EaBD35f1875DcEA89Ea97; // aArbEURS
        if (bToken == 0x5979D7b546E38E414F7E9822514be443A4800529) return 0x513c7E3a9c69cA3e22550eF58AC1C0088e918FFf; // aArbwstETH
        if (bToken == 0x3F56e0c36d275367b8C502090EDF38289b3dEa0d) return 0xc45A479877e1e9Dfe9FcD4056c699575a1045dAA; // aArbMAI
        if (bToken == 0xEC70Dcb4A1EFa46b8F2D97C310C9c4790ba5ffA8) return 0x8Eb270e296023E9D92081fdF967dDd7878724424; // aArbrETH
        if (bToken == 0x93b346b6BC2548dA6A1E7d98E9a421B42541425b) return 0x8ffDf2DE812095b1D19CB146E4c004587C0A0692; // aArbLUSD
        if (bToken == 0xaf88d065e77c8cC2239327C5EDb3A432268e5831) return 0x724dc807b04555b71ed48a6896b6F41593b8C637; // aArbUSDCn
        if (bToken == 0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F) return 0x38d693cE1dF5AaDF7bC62595A37D667aD57922e5; // aArbFRAX
        if (bToken == 0x912CE59144191C1204E64559FE8253a0e49E6548) return 0x6533afac2E7BCCB20dca161449A13A32D391fb00; // aArbARB
        revert AaveNoMarket();
    }

}
