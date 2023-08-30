// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './IComptroller.sol';
import './IMarket.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '../../library/ETHAndERC20.sol';
import '../../library/SafeMath.sol';

library VenusBnb {

    using SafeERC20 for IERC20;
    using ETHAndERC20 for address;
    using SafeMath for uint256;

    error VenusEnterMarketError();
    error VenusExitMarketError();
    error VenusDepositError();
    error VenusRedeemError();
    error VenusNoMarket();

    address constant comptroller = 0xfD36E2c2a6789Db23113685031d7F16329158384;
    address constant rewardToken = 0xcF6BB5389c92Bdda8a3747Ddb454cB7a64626C63; // XVS

    // For Venus, stToken is Venus vToken

    function getStExRate(address bToken, uint256 stTotalAmount) external view returns (uint256 stExRate) {
        if (stTotalAmount != 0) {
            address market = getMarket(bToken);
            stExRate = IMarket(market).exchangeRateStored() * market.balanceOfThis() / stTotalAmount;
        }
    }

    function enterMarket(address bToken) external {
        address market = getMarket(bToken);
        bToken.approveMax(market);
        address[] memory markets = new address[](1);
        markets[0] = market;
        uint256[] memory errors = IComptroller(comptroller).enterMarkets(markets);
        if (errors[0] != 0) {
            revert VenusEnterMarketError();
        }
    }

    function exitMarket(address bToken) external {
        address market = getMarket(bToken);
        bToken.unapprove(market);
        uint256 error = IComptroller(comptroller).exitMarket(market);
        if (error != 0) {
            revert VenusExitMarketError();
        }
    }

    function deposit(address bToken, uint256 bAmount, uint256 stTotalAmount) external returns (uint256 stAmount) {
        address market = getMarket(bToken);
        uint256 mBalance1 = market.balanceOfThis();
        if (bToken == address(1)) {
            IMarket(market).mint{value: bAmount}();
        } else {
            uint256 error = IMarket(market).mint(bAmount);
            if (error != 0) {
                revert VenusDepositError();
            }
        }
        uint256 mBalance2 = market.balanceOfThis();
        if (mBalance1 == 0) {
            stAmount = mBalance2.rescale(market.decimals(), 18);
        } else {
            stAmount = (mBalance2 - mBalance1) * stTotalAmount / mBalance1;
        }
    }

    function redeem(address bToken, uint256 stAmount, uint256 stTotalAmount) external returns (uint256 bAmount) {
        address market = getMarket(bToken);
        uint256 bBalance1 = bToken.balanceOfThis();
        uint256 mAmount = market.balanceOfThis() * stAmount / stTotalAmount;
        uint256 error = IMarket(market).redeem(mAmount);
        if (error != 0) {
            revert VenusRedeemError();
        }
        uint256 bBalance2 = bToken.balanceOfThis();
        return bBalance2 - bBalance1;
    }

    function redeemBToken(address bToken, uint256 bAmount, uint256 stTotalAmount) external returns (uint256 stAmount) {
        address market = getMarket(bToken);
        uint256 mBalance1 = market.balanceOfThis();
        uint256 bBalance1 = bToken.balanceOfThis();
        uint256 error = IMarket(market).redeemUnderlying(bAmount);
        if (error != 0) {
            revert VenusRedeemError();
        }
        uint256 mBalance2 = market.balanceOfThis();
        uint256 bBalance2 = bToken.balanceOfThis();
        if (bBalance2 != bBalance1 + bAmount) {
            revert VenusRedeemError();
        }
        return (mBalance1 - mBalance2) * stTotalAmount / mBalance1;
    }

    function claimReward(address to) external {
        uint256 rewardBalance1 = rewardToken.balanceOfThis();
        IComptroller(comptroller).claimVenus(address(this));
        uint256 rewardBalance2 = rewardToken.balanceOfThis();
        uint256 rewardAmount = rewardBalance2 - rewardBalance1;
        IERC20(rewardToken).safeTransfer(to, rewardAmount);
    }

    function getMarket(address bToken) public pure returns (address) {
        if (bToken == 0x0000000000000000000000000000000000000001) return 0xA07c5b74C9B40447a954e1466938b865b6BBea36; // vBNB
        if (bToken == 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d) return 0xecA88125a5ADbe82614ffC12D0DB554E2e2867C8; // vUSDC
        if (bToken == 0x55d398326f99059fF775485246999027B3197955) return 0xfD5840Cd36d94D7229439859C0112a4185BC0255; // vUSDT
        if (bToken == 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56) return 0x95c78222B3D6e262426483D42CfA53685A67Ab9D; // vBUSD
        if (bToken == 0x47BEAd2563dCBf3bF2c9407fEa4dC236fAbA485A) return 0x2fF3d0F6990a40261c66E1ff2017aCBc282EB6d0; // vSXP
        if (bToken == 0xcF6BB5389c92Bdda8a3747Ddb454cB7a64626C63) return 0x151B1e2635A717bcDc836ECd6FbB62B674FE3E1D; // vXVS
        if (bToken == 0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c) return 0x882C173bC7Ff3b7786CA16dfeD3DFFfb9Ee7847B; // vBTC
        if (bToken == 0x2170Ed0880ac9A755fd29B2688956BD959F933F8) return 0xf508fCD89b8bd15579dc79A6827cB4686A3592c8; // vETH
        if (bToken == 0x4338665CBB7B2485A8855A139b75D5e34AB0DB94) return 0x57A5297F2cB2c0AaC9D554660acd6D385Ab50c6B; // vLTC
        if (bToken == 0x1D2F0da169ceB9fC7B3144628dB156f3F6c60dBE) return 0xB248a295732e0225acd3337607cc01068e3b9c10; // vXRP
        if (bToken == 0x8fF795a6F4D97E7887C79beA79aba5cc76444aDf) return 0x5F0388EBc2B94FA8E123F404b79cCF5f40b29176; // vBCH
        if (bToken == 0x7083609fCE4d1d8Dc0C979AAb8c869Ea2C873402) return 0x1610bc33319e9398de5f57B33a5b184c806aD217; // vDOT
        if (bToken == 0xF8A0BF9cF54Bb92F17374d9e9A321E6a111a51bD) return 0x650b940a1033B8A1b1873f78730FcFC73ec11f1f; // vLINK
        if (bToken == 0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3) return 0x334b3eCB4DCa3593BCCC3c7EBD1A1C1d1780FBF1; // vDAI
        if (bToken == 0x0D8Ce2A99Bb6e3B7Db580eD848240e4a0F9aE153) return 0xf91d58b5aE142DAcC749f58A49FCBac340Cb0343; // vFIL
        if (bToken == 0x250632378E573c6Be1AC2f97Fcdf00515d0Aa91B) return 0x972207A639CC1B374B893cc33Fa251b55CEB7c07; // vBETH
        if (bToken == 0x20bff4bbEDa07536FF00e073bd8359E5D80D733d) return 0xeBD0070237a0713E8D94fEf1B728d3d993d290ef; // vCAN
        if (bToken == 0x3EE2200Efb3400fAbB9AacF31297cBdD1d435D47) return 0x9A0AF7FDb2065Ce470D72664DE73cAE409dA28Ec; // vADA
        if (bToken == 0xbA2aE424d960c26247Dd6c32edC70B295c744C43) return 0xec3422Ef92B2fb59e84c8B02Ba73F1fE84Ed8D71; // vDOGE
        if (bToken == 0xCC42724C6683B7E57334c4E856f4c9965ED682bD) return 0x5c9476FcD6a4F9a3654139721c949c2233bBbBc8; // vMATIC
        if (bToken == 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82) return 0x86aC3974e2BD0d60825230fa6F355fF11409df5c; // vCAKE
        if (bToken == 0xfb6115445Bff7b52FeB98650C87f44907E58f802) return 0x26DA28954763B92139ED49283625ceCAf52C6f94; // vAAVE
        if (bToken == 0x14016E85a25aeb13065688cAFB43044C2ef86784) return 0x08CEB3F4a7ed3500cA0982bcd0FC7816688084c3; // vTUSDOLD
        if (bToken == 0x85EAC5Ac2F758618dFa09bDbe0cf174e7d574D5B) return 0x61eDcFe8Dd6bA3c891CB9bEc2dc7657B3B422E93; // vTRXOLD
        if (bToken == 0x3d4350cD54aeF9f9b2C29435e0fa809957B3F30a) return 0x78366446547D062f45b4C0f320cDaa6d710D87bb; // vUST
        if (bToken == 0x156ab3346823B651294766e23e6Cf87254d68962) return 0xb91A659E88B51474767CD97EF3196A3e7cEDD2c8; // vLUNA
        if (bToken == 0xCE7de646e7208a4Ef112cb6ed5038FA6cC6b12e3) return 0xC5D3466aA484B040eE977073fcF337f2c00071c1; // vTRX
        if (bToken == 0xa2E3356610840701BDf5611a53974510Ae27E2e1) return 0x6CFdEc747f37DAf3b87a35a1D9c8AD3063A1A8A0; // vWBETH
        if (bToken == 0x40af3827F39D0EAcBF4A168f8D4ee67c121D11c9) return 0xBf762cd5991cA1DCdDaC9ae5C638F5B5Dc3Bee6E; // vTUSD
        revert VenusNoMarket();
    }

}
