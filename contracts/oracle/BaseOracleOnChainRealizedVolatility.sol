// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './IOracle.sol';
import '../library/PRBMathSD59x18.sol';
import '../library/SafeMath.sol';
import '../utils/Admin.sol';

// @title On-chain realized volatility oracle with online algorithm,
// by tracking an on-chain price oracle
// more details about the algorithm:
// https://im0xalpha.notion.site/An-Online-Algorithm-of-Realized-Vol-b20b3ff31f9448eea6be42c4b5052361

contract BaseOracleOnChainRealizedVolatility is Admin {
    using SafeMath for uint256;

    event NewRealizedVolatility(bytes32 oracleId, uint256 timestamp, int256 price, int256 volatility);

    struct Info {
        bytes32 priceId;
        address priceOracle;
        int256  tau;
        uint256 timestamp;
        int256  price;
        int256  volatility;
    }

    int256 constant ONE = 1e18;

    // oracleId => Info
    mapping (bytes32 => Info) public infos;

    function set(
        string memory symbol,
        string memory priceSymbol,
        address priceOracle,
        int256 tau,
        int256 initPrice,
        int256 initVolatility
    ) external _onlyAdmin_ {
        bytes32 oracleId = keccak256(abi.encodePacked(symbol));
        bytes32 priceId = keccak256(abi.encodePacked(priceSymbol));
        infos[oracleId].priceId = priceId;
        infos[oracleId].priceOracle = priceOracle;
        infos[oracleId].tau = tau;
        infos[oracleId].timestamp = block.timestamp;
        infos[oracleId].price = initPrice;
        infos[oracleId].volatility = initVolatility;
    }

    function getValue(bytes32 oracleId) external view returns (int256) {
        return infos[oracleId].volatility;
    }

    function getValueCurrentBlock(bytes32 oracleId) external returns (int256) {
        Info memory info = infos[oracleId];
        if (block.timestamp > info.timestamp) {
            int256 deltaT = (block.timestamp - info.timestamp).utoi();
            int256 currentPrice = IOracle(info.priceOracle).getValueCurrentBlock(info.priceId);
            int256 r = currentPrice * ONE / info.price - ONE;
            int256 variance = r ** 2 / ONE * info.tau / ONE * 31536000 + info.volatility ** 2 / ONE * (ONE - info.tau * deltaT) / ONE;
            int256 volatility = PRBMathSD59x18.sqrt(variance);

            infos[oracleId].timestamp = block.timestamp;
            infos[oracleId].price = currentPrice;
            infos[oracleId].volatility = volatility;

            emit NewRealizedVolatility(oracleId, block.timestamp, currentPrice, volatility);
            return volatility;
        } else {
            return info.volatility;
        }
    }

}
