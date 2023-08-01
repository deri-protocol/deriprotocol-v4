// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IOracle.sol';
import '../interface/IChainlinkFeed.sol';
import '../library/Bytes32Map.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import './OracleStorage.sol';

contract OracleImplementation is OracleStorage {

    using Bytes32Map for mapping(uint8 => bytes32);

    error InvalidSignature();
    error NoSource(bytes32 oracleId, uint256 source);
    error OracleValueExpired(bytes32 oracleId, string symbol);

    event NewValue(bytes32 oracleId, uint256 timestamp, int256 value);

    uint8 constant S_SYMBOL         = 1;
    uint8 constant S_SOURCE         = 2;
    uint8 constant S_DELAYALLOWANCE = 3;
    uint8 constant S_BLOCKNUMBER    = 4;
    uint8 constant S_TIMESTAMP      = 5;
    uint8 constant S_VALUE          = 6;
    uint8 constant S_CHAINLINKFEED  = 7;

    uint256 constant SOURCE_OFFCHAIN  = 1;
    uint256 constant SOURCE_CHAINLINK = 2;

    function setOffchainOracle(string memory symbol, uint256 delayAllowance) external _onlyAdmin_ {
        bytes32 oracleId = keccak256(abi.encodePacked(symbol));
        _states[oracleId].set(S_SYMBOL, symbol);
        _states[oracleId].set(S_SOURCE, SOURCE_OFFCHAIN);
        _states[oracleId].set(S_DELAYALLOWANCE, delayAllowance);
        _states[oracleId].set(S_VALUE, int256(1));
    }

    function setChainlinkOracle(string memory symbol, address feed) external _onlyAdmin_ {
        bytes32 oracleId = keccak256(abi.encodePacked(symbol));
        _states[oracleId].set(S_SYMBOL, symbol);
        _states[oracleId].set(S_SOURCE, SOURCE_CHAINLINK);
        _states[oracleId].set(S_CHAINLINKFEED, feed);
    }

    function getState(bytes32 oracleId) public view returns (IOracle.State memory s) {
        s.symbol = _states[oracleId].getString(S_SYMBOL);
        s.source = _states[oracleId].getUint(S_SOURCE);
        s.delayAllowance = _states[oracleId].getUint(S_DELAYALLOWANCE);
        s.blockNumber = _states[oracleId].getUint(S_BLOCKNUMBER);
        s.timestamp = _states[oracleId].getUint(S_TIMESTAMP);
        s.value = _states[oracleId].getInt(S_VALUE);
        s.chainlinkFeed = _states[oracleId].getAddress(S_CHAINLINKFEED);
    }

    // Get value without check
    function getValueNoCheck(bytes32 oracleId) public view returns (int256 value) {
        (, , value) = _getValue(oracleId);
    }

    function getValue(bytes32 oracleId) public view returns (int256) {
        (uint256 blockNumber, , int256 value) = _getValue(oracleId);
        if (blockNumber != block.number) {
            revert OracleValueExpired(oracleId, _states[oracleId].getString(S_SYMBOL));
        }
        return value;
    }

    function updateOffchainValue(IOracle.Signature memory sig) external returns (bool) {
        bytes32 hash = ECDSA.toEthSignedMessageHash(
            keccak256(abi.encodePacked(sig.oracleId, sig.timestamp, sig.value))
        );
        if (ECDSA.recover(hash, sig.v, sig.r, sig.s) != signer) {
            revert InvalidSignature();
        }
        return _updateOffchainValue(sig.oracleId, sig.timestamp, sig.value);
    }

    //================================================================================

    function _getValue(bytes32 oracleId)
    internal view returns (uint256 blockNumber, uint256 timestamp, int256 value)
    {
        uint256 source = _states[oracleId].getUint(S_SOURCE);
        if (source == SOURCE_OFFCHAIN) {
            return _getValueOfOffchain(oracleId);
        } else if (source == SOURCE_CHAINLINK) {
            return _getValueOfChainlink(oracleId);
        } else {
            revert NoSource(oracleId, source);
        }
    }

    function _getValueOfOffchain(bytes32 oracleId)
    internal view returns (uint256 blockNumber, uint256 timestamp, int256 value)
    {
        blockNumber = _states[oracleId].getUint(S_BLOCKNUMBER);
        timestamp = _states[oracleId].getUint(S_TIMESTAMP);
        value = _states[oracleId].getInt(S_VALUE);
        if (value == 0) {
            revert NoSource(oracleId, SOURCE_OFFCHAIN);
        }
    }

    function _getValueOfChainlink(bytes32 oracleId)
    internal view returns (uint256 blockNumber, uint256 timestamp, int256 value)
    {
        address feed = _states[oracleId].getAddress(S_CHAINLINKFEED);
        if (feed == address(0)) {
            revert NoSource(oracleId, SOURCE_CHAINLINK);
        }
        blockNumber = block.number;
        (, value, , timestamp, ) = IChainlinkFeed(feed).latestRoundData();
        uint8 decimals = IChainlinkFeed(feed).decimals();
        if (decimals != 18) {
            value *= int256(10 ** (18 - decimals));
        }
    }

    function _updateOffchainValue(bytes32 oracleId, uint256 timestamp, int256 value) internal returns (bool) {
        uint256 lastBlockNumber = _states[oracleId].getUint(S_BLOCKNUMBER);
        uint256 lastTimestamp = _states[oracleId].getUint(S_TIMESTAMP);
        uint256 delayAllowance = _states[oracleId].getUint(S_DELAYALLOWANCE);
        if (block.number > lastBlockNumber && timestamp > lastTimestamp && block.timestamp < timestamp + delayAllowance) {
            _states[oracleId].set(S_BLOCKNUMBER, block.number);
            _states[oracleId].set(S_TIMESTAMP, timestamp);
            _states[oracleId].set(S_VALUE, value);
            emit NewValue(oracleId, timestamp, value);
            return true;
        } else {
            return false;
        }
    }

}
