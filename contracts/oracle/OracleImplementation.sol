// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './IOracle.sol';
import './IChainlinkFeed.sol';
import '../library/Bytes32Map.sol';
import './OracleStorage.sol';

contract OracleImplementation is OracleStorage {

    using Bytes32Map for mapping(uint8 => bytes32);

    error NoSource();
    error InvalidFeed();
    error OracleValueExpired();

    event NewOracle(bytes32 oracleId, uint256 source);
    event NewOffchainValue(bytes32 oracleId, uint256 timestamp, int256 value);

    uint8 constant S_SYMBOL         = 1; // oracle symbol, less than 32 characters
    uint8 constant S_SOURCE         = 2; // oracle source, e.g. offchain or chainlink
    uint8 constant S_DELAYALLOWANCE = 3; // when use offchain source, max delay allowed for valid update
    uint8 constant S_BLOCKNUMBER    = 4; // when use offchain source, the block number in which value updated
    uint8 constant S_TIMESTAMP      = 5; // when use offchain source, the oracle value timestamp
    uint8 constant S_VALUE          = 6; // when use offchain source, the oracle value
    uint8 constant S_CHAINLINKFEED  = 7; // when use chainlink source, the chainlink feed

    uint256 constant SOURCE_OFFCHAIN  = 1;
    uint256 constant SOURCE_CHAINLINK = 2;

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

    function _getValue(bytes32 oracleId)
    internal view returns (uint256 blockNumber, uint256 timestamp, int256 value)
    {
        uint256 source = _states[oracleId].getUint(S_SOURCE);
        if (source == SOURCE_OFFCHAIN) {
            return _getValueOffchain(oracleId);
        } else if (source == SOURCE_CHAINLINK) {
            return _getValueChainlink(oracleId);
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
