// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../utils/Admin.sol';
import '../library/OracleLibrary.sol';
import '../library/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

contract BaseOracleIzumi is Admin {

    using SafeMath for uint256;

    struct Info {
        address pool;
        address baseToken;
        address quoteToken;
        uint32  secondsAgo;
    }

    // oracleId => Info
    mapping (bytes32 => Info) public infos;

    function set(
        string memory symbol,
        address pool,
        address baseToken,
        address quoteToken,
        uint32 secondsAgo
    ) external _onlyAdmin_
    {
        address tokenX = IIzumiPool(pool).tokenX();
        address tokenY = IIzumiPool(pool).tokenY();
        require(
            (baseToken == tokenX || baseToken == tokenY) &&
            (quoteToken == tokenX || quoteToken == tokenY)
        );

        bytes32 oracleId = keccak256(abi.encodePacked(symbol));
        infos[oracleId].pool = pool;
        infos[oracleId].baseToken = baseToken;
        infos[oracleId].quoteToken = quoteToken;
        infos[oracleId].secondsAgo = secondsAgo;
    }

    function getValue(bytes32 oracleId) public view returns (int256) {
        Info storage info = infos[oracleId];

        int24 arithmeticMeanTick;
        {
            uint32 secondsAgo = info.secondsAgo;
            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = secondsAgo;
            secondsAgos[1] = 0;

            int56[] memory tickCumulatives = IIzumiPool(info.pool).observe(secondsAgos);
            int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
            arithmeticMeanTick = int24(tickCumulativesDelta / int56(uint56(secondsAgo)));
            if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(uint56(secondsAgo)) != 0)) arithmeticMeanTick--;
        }

        uint256 quoteAmount = OracleLibrary.getQuoteAtTick(
            arithmeticMeanTick,
            uint128(10 ** (IERC20Metadata(info.baseToken).decimals())),
            info.baseToken,
            info.quoteToken
        );

        uint8 quoteDecimals = IERC20Metadata(info.quoteToken).decimals();
        if (quoteDecimals != 18) {
            quoteAmount *= 10 ** (18 - quoteDecimals);
        }

        return quoteAmount.utoi();
    }

    function getValueCurrentBlock(bytes32 oracleId) public view returns (int256) {
        return getValue(oracleId);
    }

}


interface IIzumiPool {
    function tokenX() external view returns (address);
    function tokenY() external view returns (address);
    function observe(uint32[] calldata secondsAgos) external view returns (int56[] memory accPoints);
}
