// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {ProjectFacet} from '../../project-contracts/ProjectFacet.sol';
import {IAccessControlEoa} from '@red-isbe/isbe-contracts/contracts/access/accessControl/IAccessControlEoa.sol';
import {_DEFAULT_ADMIN_ROLE} from '@red-isbe/isbe-contracts/contracts/constants/roles.sol';
import {_PROJECT_ROLE} from '../../constants/constants.sol';

/// @title ProjectTestWrapper
/// @notice Test wrapper for ProjectFacet that exposes initialization helpers
/// @dev Only for use in tests — never deploy to production
abstract contract ProjectTestWrapper is ProjectFacet {
    /// @notice Initializes roles for standalone testing (no governance infrastructure needed)
    /// @param customerAccount Address to grant DEFAULT_ADMIN_ROLE and _PROJECT_ROLE
    function initializeForTest(address customerAccount) external {
        address[] memory adminMembers = new address[](1);
        adminMembers[0] = customerAccount;

        address[] memory custMembers = new address[](1);
        custMembers[0] = customerAccount;

        IAccessControlEoa.Rbac[] memory rbacs = new IAccessControlEoa.Rbac[](2);
        rbacs[0] = IAccessControlEoa.Rbac({
            role: _DEFAULT_ADMIN_ROLE,
            members: adminMembers
        });
        rbacs[1] = IAccessControlEoa.Rbac({
            role: _PROJECT_ROLE,
            members: custMembers
        });

        _initializeRbacs(rbacs);
    }

    /// @notice Pauses the contract for testing pause-related behaviour
    function pauseForTest() external {
        _pauseStorage().pause = true;
    }
}