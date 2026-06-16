// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {HashTimestampFacet} from '../../example-hashtimestamp/HashTimestampFacet.sol';
import {IAccessControlEoa} from '@red-isbe/isbe-contracts/contracts/access/accessControl/IAccessControlEoa.sol';
import {_DEFAULT_ADMIN_ROLE} from '@red-isbe/isbe-contracts/contracts/constants/roles.sol';
import {_HASH_TIMESTAMP_ROLE} from '../../constants/constants.sol';

/// @title HashTimestampTestWrapper
/// @notice Test wrapper for HashTimestampFacet that exposes initialization helpers
/// @dev Only for use in tests — never deploy to production
contract HashTimestampTestWrapper is HashTimestampFacet {
    /// @notice Initializes roles for standalone testing (no governance infrastructure needed)
    /// @param account Address to grant DEFAULT_ADMIN_ROLE and HASH_TIMESTAMP_ROLE
    function initializeForTest(address account) external {
        address[] memory adminMembers = new address[](1);
        adminMembers[0] = account;

        address[] memory roleMembers = new address[](1);
        roleMembers[0] = account;

        IAccessControlEoa.Rbac[] memory rbacs = new IAccessControlEoa.Rbac[](2);
        rbacs[0] = IAccessControlEoa.Rbac({
            role: _DEFAULT_ADMIN_ROLE,
            members: adminMembers
        });
        rbacs[1] = IAccessControlEoa.Rbac({
            role: _HASH_TIMESTAMP_ROLE,
            members: roleMembers
        });

        _initializeRbacs(rbacs);
    }

    /// @notice Pauses the contract for testing pause-related behaviour
    function pauseForTest() external {
        _pauseStorage().pause = true;
    }
}
