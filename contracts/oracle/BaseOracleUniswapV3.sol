// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../utils/Admin.sol';
import './OracleLibrary.sol';
import '../library/SafeMath.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

contract BaseOracleUniswapV3 is Admin {

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
        address token0 = IUniswapV3Pool(pool).token0();
        address token1 = IUniswapV3Pool(pool).token1();
        require(
            (baseToken == token0 || baseToken == token1) &&
            (quoteToken == token0 || quoteToken == token1)
        );

        bytes32 oracleId = keccak256(abi.encodePacked(symbol));
        infos[oracleId].pool = pool;
        infos[oracleId].baseToken = baseToken;
        infos[oracleId].quoteToken = quoteToken;
        infos[oracleId].secondsAgo = secondsAgo;
    }

    // @notice Get oracle value without any checking
    function getValue(bytes32 oracleId) public view returns (int256) {
        Info storage info = infos[oracleId];

        (int24 arithmeticMeanTick, ) = OracleLibrary.consult(info.pool, info.secondsAgo);
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

    // @notice Get oracle value of current block
    // @dev When source is offchain, value must be updated in current block, otherwise revert
    function getValueCurrentBlock(bytes32 oracleId) public view returns (int256) {
        return getValue(oracleId);
    }

}
