// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './IOracle.sol';
import './IChainlinkFeed.sol';
import '../library/SafeMath.sol';
import '../library/Bytes32Map.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import './OracleLibrary.sol';
import './OracleStorage.sol';

contract OracleImplementation is OracleStorage {

    using SafeMath for uint256;
    using Bytes32Map for mapping(uint8 => bytes32);

    error NoSource();
    error InvalidFeed();
    error OracleValueExpired();
    error InvalidUniswapV3Pool();

    event NewOracle(bytes32 oracleId, uint256 source);
    event NewOffchainValue(bytes32 oracleId, uint256 timestamp, int256 value);

    uint8 constant S_SYMBOL         = 1; // oracle symbol, less than 32 characters
    uint8 constant S_SOURCE         = 2; // oracle source, e.g. offchain or chainlink
    uint8 constant S_DELAYALLOWANCE = 3; // when use offchain source, max delay allowed for valid update
    uint8 constant S_BLOCKNUMBER    = 4; // when use offchain source, the block number in which value updated
    uint8 constant S_TIMESTAMP      = 5; // when use offchain source, the oracle value timestamp
    uint8 constant S_VALUE          = 6; // when use offchain source, the oracle value
    uint8 constant S_CHAINLINKFEED  = 7; // when use chainlink source, the chainlink feed
    uint8 constant S_UNISWAPV3POOL  = 8; // when use uniswapV3 oracle, the swap pool
    uint8 constant S_BASETOKEN      = 9; // when use uniswapV3 oracle, the base token
    uint8 constant S_QUOTETOKEN     = 10; // when use uniswapV3 oracle, the quote token
    uint8 constant S_SECONDSAGO     = 11; // when use uniswapV3 oracle, the consult seconds ago
    uint8 constant S_QUOTEORACLEID  = 12; // when use uniswapV3 oracle, the quote oracleId

    uint256 constant SOURCE_OFFCHAIN  = 1;
    uint256 constant SOURCE_CHAINLINK = 2;
    uint256 constant SOURCE_UNISWAPV3 = 3;
    uint256 constant SOURCE_IZUMI     = 4;

    int256 constant ONE = 1e18;

    //================================================================================
    // Getters
    //================================================================================

    function getOracleId(string memory symbol) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(symbol));
    }

    function getState(bytes32 oracleId) external view returns (IOracle.State memory s) {
        s.symbol = _states[oracleId].getString(S_SYMBOL);
        s.source = _states[oracleId].getUint(S_SOURCE);
        s.delayAllowance = _states[oracleId].getUint(S_DELAYALLOWANCE);
        s.blockNumber = _states[oracleId].getUint(S_BLOCKNUMBER);
        s.timestamp = _states[oracleId].getUint(S_TIMESTAMP);
        s.value = _states[oracleId].getInt(S_VALUE);
        s.chainlinkFeed = _states[oracleId].getAddress(S_CHAINLINKFEED);
    }

    // @notice Get oracle value without any checking
    function getValue(bytes32 oracleId) public view returns (int256) {
        (, , int256 value) = _getValue(oracleId);
        return value;
    }

    // @notice Get oracle value of current block
    // @dev When source is offchain, value must be updated in current block, otherwise revert
    function getValueCurrentBlock(bytes32 oracleId) public view returns (int256) {
        (uint256 blockNumber, , int256 value) = _getValue(oracleId);
        if (blockNumber != block.number) {
            revert OracleValueExpired();
        }
        return value;
    }

    //================================================================================
    // Setters
    //================================================================================

    // @notice Set new offchain oracle
    function setOffchainOracle(string memory symbol, uint256 delayAllowance, int256 value) external _onlyAdmin_ {
        bytes32 oracleId = getOracleId(symbol);
        _states[oracleId].set(S_SYMBOL, symbol);
        _states[oracleId].set(S_SOURCE, SOURCE_OFFCHAIN);
        _states[oracleId].set(S_DELAYALLOWANCE, delayAllowance);
        _states[oracleId].set(S_VALUE, value);
        emit NewOracle(oracleId, SOURCE_OFFCHAIN);
    }

    // @notice Set new Chainlink oracle
    function setChainlinkOracle(string memory symbol, address feed) external _onlyAdmin_ {
        bytes32 oracleId = getOracleId(symbol);
        _states[oracleId].set(S_SYMBOL, symbol);
        _states[oracleId].set(S_SOURCE, SOURCE_CHAINLINK);
        _states[oracleId].set(S_CHAINLINKFEED, feed);
        _getValue(oracleId); // make sure chainlink feed works
        emit NewOracle(oracleId, SOURCE_CHAINLINK);
    }

    function setUniswapV3Oracle(
        string memory symbol,
        address pool,
        address baseToken,
        address quoteToken,
        uint256 secondsAgo,
        bytes32 quoteOracleId
    ) external _onlyAdmin_ {
        bytes32 oracleId = getOracleId(symbol);
        address token0 = IUniswapV3Pool(pool).token0();
        address token1 = IUniswapV3Pool(pool).token1();
        require(
            (baseToken == token0 || baseToken == token1) &&
            (quoteToken == token0 || quoteToken == token1)
        );
        _states[oracleId].set(S_SYMBOL, symbol);
        _states[oracleId].set(S_SOURCE, SOURCE_UNISWAPV3);
        _states[oracleId].set(S_UNISWAPV3POOL, pool);
        _states[oracleId].set(S_BASETOKEN, baseToken);
        _states[oracleId].set(S_QUOTETOKEN, quoteToken);
        _states[oracleId].set(S_SECONDSAGO, secondsAgo);
        _states[oracleId].set(S_QUOTEORACLEID, quoteOracleId);
        if (quoteOracleId != bytes32(0)) {
            getValue(quoteOracleId); // make sure quote oracle works
        }
        emit NewOracle(oracleId, SOURCE_UNISWAPV3);
    }

    function setIzumiOracle(
        string memory symbol,
        address pool,
        address baseToken,
        address quoteToken,
        uint256 secondsAgo,
        bytes32 quoteOracleId
    ) external _onlyAdmin_ {
        bytes32 oracleId = getOracleId(symbol);
        address tokenX = IIzumiPool(pool).tokenX();
        address tokenY = IIzumiPool(pool).tokenY();
        require(
            (baseToken == tokenX || baseToken == tokenY) &&
            (quoteToken == tokenX || quoteToken == tokenY)
        );
        _states[oracleId].set(S_SYMBOL, symbol);
        _states[oracleId].set(S_SOURCE, SOURCE_IZUMI);
        _states[oracleId].set(S_UNISWAPV3POOL, pool);
        _states[oracleId].set(S_BASETOKEN, baseToken);
        _states[oracleId].set(S_QUOTETOKEN, quoteToken);
        _states[oracleId].set(S_SECONDSAGO, secondsAgo);
        _states[oracleId].set(S_QUOTEORACLEID, quoteOracleId);
        if (quoteOracleId != bytes32(0)) {
            getValue(quoteOracleId); // make sure quote oracle works
        }
        emit NewOracle(oracleId, SOURCE_IZUMI);
    }

    function updateOffchainValue(IOracle.Signature memory sig) public {
        bytes32 message = keccak256(abi.encodePacked(sig.oracleId, sig.timestamp, sig.value));
        _verifyMessage(message, sig.v, sig.r, sig.s);
        _updateOffchainValue(sig.oracleId, sig.timestamp, sig.value);
    }

    function updateOffchainValues(IOracle.Signature[] memory sigs) external {
        for (uint256 i = 0; i < sigs.length; i++) {
            updateOffchainValue(sigs[i]);
        }
    }

    //================================================================================
    // Internals
    //================================================================================

    function _getValueOffchain(bytes32 oracleId)
    internal view returns (uint256 blockNumber, uint256 timestamp, int256 value)
    {
        blockNumber = _states[oracleId].getUint(S_BLOCKNUMBER);
        timestamp = _states[oracleId].getUint(S_TIMESTAMP);
        value = _states[oracleId].getInt(S_VALUE);
    }

    function _getValueChainlink(bytes32 oracleId)
    internal view returns (uint256 blockNumber, uint256 timestamp, int256 value)
    {
        address feed = _states[oracleId].getAddress(S_CHAINLINKFEED);
        if (feed == address(0)) {
            revert InvalidFeed();
        }
        blockNumber = block.number; // for Chainlink, just return current block number
        (, value, , timestamp, ) = IChainlinkFeed(feed).latestRoundData();
        uint8 decimals = IChainlinkFeed(feed).decimals();
        if (decimals != 18) {
            value *= int256(10 ** (18 - decimals));
        }
    }

    function _getValueUniswapV3(bytes32 oracleId)
    internal view returns (uint256 blockNumber, uint256 timestamp, int256 value)
    {
        address pool = _states[oracleId].getAddress(S_UNISWAPV3POOL);
        if (pool == address(0)) {
            revert InvalidUniswapV3Pool();
        }
        address baseToken = _states[oracleId].getAddress(S_BASETOKEN);
        address quoteToken = _states[oracleId].getAddress(S_QUOTETOKEN);
        uint32 secondsAgo = uint32(_states[oracleId].getUint(S_SECONDSAGO));

        (int24 arithmeticMeanTick, ) = OracleLibrary.consult(pool, secondsAgo);
        uint256 quoteAmount = OracleLibrary.getQuoteAtTick(
            arithmeticMeanTick,
            uint128(10 ** (IERC20Metadata(baseToken).decimals())),
            baseToken,
            quoteToken
        );

        uint8 quoteDecimals = IERC20Metadata(quoteToken).decimals();
        if (quoteDecimals != 18) {
            quoteAmount *= 10 ** (18 - quoteDecimals);
        }

        value = quoteAmount.utoi();
        bytes32 quoteOracleId = _states[oracleId].getBytes32(S_QUOTEORACLEID);
        if (quoteOracleId != bytes32(0)) {
            value = value * getValue(quoteOracleId) / ONE;
        }

        return (block.number, block.timestamp, value);
    }

    function _getValueIzumi(bytes32 oracleId)
    internal view returns (uint256 blockNumber, uint256 timestamp, int256 value)
    {
        address pool = _states[oracleId].getAddress(S_UNISWAPV3POOL);
        if (pool == address(0)) {
            revert InvalidUniswapV3Pool();
        }
        address baseToken = _states[oracleId].getAddress(S_BASETOKEN);
        address quoteToken = _states[oracleId].getAddress(S_QUOTETOKEN);
        uint32 secondsAgo = uint32(_states[oracleId].getUint(S_SECONDSAGO));

        int24 arithmeticMeanTick;
        {
            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = secondsAgo;
            secondsAgos[1] = 0;

            int56[] memory tickCumulatives = IIzumiPool(pool).observe(secondsAgos);
            int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
            arithmeticMeanTick = int24(tickCumulativesDelta / int56(uint56(secondsAgo)));
            if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(uint56(secondsAgo)) != 0)) arithmeticMeanTick--;
        }

        uint256 quoteAmount = OracleLibrary.getQuoteAtTick(
            arithmeticMeanTick,
            uint128(10 ** (IERC20Metadata(baseToken).decimals())),
            baseToken,
            quoteToken
        );

        uint8 quoteDecimals = IERC20Metadata(quoteToken).decimals();
        if (quoteDecimals != 18) {
            quoteAmount *= 10 ** (18 - quoteDecimals);
        }

        value = quoteAmount.utoi();
        bytes32 quoteOracleId = _states[oracleId].getBytes32(S_QUOTEORACLEID);
        if (quoteOracleId != bytes32(0)) {
            value = value * getValue(quoteOracleId) / ONE;
        }

        return (block.number, block.timestamp, value);
    }

    function _getValue(bytes32 oracleId)
    internal view returns (uint256 blockNumber, uint256 timestamp, int256 value)
    {
        uint256 source = _states[oracleId].getUint(S_SOURCE);
        if (source == SOURCE_OFFCHAIN) {
            return _getValueOffchain(oracleId);
        } else if (source == SOURCE_CHAINLINK) {
            return _getValueChainlink(oracleId);
        } else if (source == SOURCE_UNISWAPV3) {
            return _getValueUniswapV3(oracleId);
        } else if (source == SOURCE_IZUMI) {
            return _getValueIzumi(oracleId);
        } else {
            revert NoSource();
        }
    }

    function _updateOffchainValue(bytes32 oracleId, uint256 timestamp, int256 value) internal {
        uint256 lastBlockNumber = _states[oracleId].getUint(S_BLOCKNUMBER);
        uint256 lastTimestamp = _states[oracleId].getUint(S_TIMESTAMP);
        uint256 delayAllowance = _states[oracleId].getUint(S_DELAYALLOWANCE);
        if (
            block.number > lastBlockNumber &&            // Offchain oracle only can be updated once in same block
            timestamp > lastTimestamp &&                 // Update value must be newer
            block.timestamp < timestamp + delayAllowance // New value must not expire, e.g. in delay allowance
        ) {
            _states[oracleId].set(S_BLOCKNUMBER, block.number);
            _states[oracleId].set(S_TIMESTAMP, timestamp);
            _states[oracleId].set(S_VALUE, value);
            emit NewOffchainValue(oracleId, timestamp, value);
        }
    }

}

interface IIzumiPool {
    function tokenX() external view returns (address);
    function tokenY() external view returns (address);
    function observe(uint32[] calldata secondsAgos) external view returns (int56[] memory accPoints);
}
