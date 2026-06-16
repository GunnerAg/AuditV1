// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

contract HashTimestampStandalone {
    event HashTimestamped(
        bytes32 indexed hash,
        address indexed sender,
        uint256 timestamp
    );

    error HashAlreadyExists(bytes32 hash);

    mapping(bytes32 => uint256) private hashTimestamps;

    function timestampHash(bytes32 _hash) external {
        require(hashTimestamps[_hash] == 0, HashAlreadyExists(_hash));

        uint256 timestamp = block.timestamp;
        hashTimestamps[_hash] = timestamp;

        emit HashTimestamped(_hash, msg.sender, timestamp);
    }

    function exists(bytes32 _hash) external view returns (bool) {
        return hashTimestamps[_hash] != 0;
    }

    function getTimestamp(bytes32 _hash) external view returns (uint256) {
        return hashTimestamps[_hash];
    }
}
