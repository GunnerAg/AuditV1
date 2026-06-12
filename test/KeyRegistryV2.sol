// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../KeyRegistry.sol";

/**
 * @title KeyRegistryV2
 * @notice Mock V2 of KeyRegistry for UUPS upgrade tests.
 * @dev Overrides version() to return "2". All storage and logic inherited from V1.
 *      Placed in contracts/test/ so it doesn't appear in production builds.
 */
contract KeyRegistryV2 is KeyRegistry {
    function version() external pure override returns (string memory) {
        return "2";
    }
}
