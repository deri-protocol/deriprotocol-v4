// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../utils/Admin.sol';

contract BaseOracleChainlink is Admin {

    // oracleId => feed
    mapping (bytes32 => address) public chainlinkFeeds;

    uint256 private constant STALENESS_THRESHOLD = 1 hours;

    function set(string memory symbol, address feed) external _onlyAdmin_ {
        bytes32 oracleId = keccak256(abi.encodePacked(symbol));
        chainlinkFeeds[oracleId] = feed;
    }

    function getValue(bytes32 oracleId) public view returns (int256) {
        IChainlinkFeed feed = IChainlinkFeed(chainlinkFeeds[oracleId]);
        (uint80 roundId, int256 value, , uint256 updatedAt, uint80 answeredInRound) = feed.latestRoundData();

        require(value > 0, 'Invalid price');
        require(updatedAt != 0 && block.timestamp - updatedAt <= STALENESS_THRESHOLD, 'Stale price');
        require(answeredInRound >= roundId, 'Incomplete round');

        uint8 decimals = feed.decimals();
        if (decimals != 18) {
            value *= int256(10 ** (18 - decimals));
        }
        return value;
    }

    function getValueCurrentBlock(bytes32 oracleId) public view returns (int256) {
        return getValue(oracleId);
    }

}


interface IChainlinkFeed {
    function decimals() external view returns (uint8);
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}
