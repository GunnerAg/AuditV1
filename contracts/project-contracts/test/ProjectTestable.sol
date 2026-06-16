// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {ProjectFacet} from "../ProjectFacet.sol";
import {IAccessControlEoa} from "@red-isbe/isbe-contracts/contracts/access/accessControl/IAccessControlEoa.sol";
import {_DEFAULT_ADMIN_ROLE} from "@red-isbe/isbe-contracts/contracts/constants/roles.sol";
import {
    _PROJECT_ROLE,
    _PROJECT_SCHEMA_MANAGER_ROLE,
    _PROJECT_ALGORITHM_MANAGER_ROLE,
    _PROJECT_KEY_MANAGER_ROLE,
    _PROJECT_KEY_REVOKER_ROLE,
    _PROJECT_ANCHOR_ROLE
} from "../../constants/constants.sol";

/// @title ProjectTestable
/// @notice Concrete test wrapper for ProjectFacet that exposes initialization helpers
///         and a pause helper. Mirrors the structure of the template's existing
///         abstract ProjectTestWrapper but is concrete so it can be deployed
///         directly in unit tests.
/// @dev Test-only. Never deploy to production.
contract ProjectTestable is ProjectFacet {
    /// @notice Grants every project role to `admin` and every role to `roleHolder`
    ///         so a single signer can exercise the full surface in tests.
    /// @param admin Address granted DEFAULT_ADMIN_ROLE and _PROJECT_ROLE.
    /// @param roleHolder Address granted every fine-grained project role.
    function initializeForTest(address admin, address roleHolder) external {
        address[] memory adminMembers = new address[](1);
        adminMembers[0] = admin;

        address[] memory holderMembers = new address[](1);
        holderMembers[0] = roleHolder;

        IAccessControlEoa.Rbac[] memory rbacs = new IAccessControlEoa.Rbac[](7);
        rbacs[0] = IAccessControlEoa.Rbac({
            role: _DEFAULT_ADMIN_ROLE,
            members: adminMembers
        });
        rbacs[1] = IAccessControlEoa.Rbac({
            role: _PROJECT_ROLE,
            members: adminMembers
        });
        rbacs[2] = IAccessControlEoa.Rbac({
            role: _PROJECT_SCHEMA_MANAGER_ROLE,
            members: holderMembers
        });
        rbacs[3] = IAccessControlEoa.Rbac({
            role: _PROJECT_ALGORITHM_MANAGER_ROLE,
            members: holderMembers
        });
        rbacs[4] = IAccessControlEoa.Rbac({
            role: _PROJECT_KEY_MANAGER_ROLE,
            members: holderMembers
        });
        rbacs[5] = IAccessControlEoa.Rbac({
            role: _PROJECT_KEY_REVOKER_ROLE,
            members: holderMembers
        });
        rbacs[6] = IAccessControlEoa.Rbac({
            role: _PROJECT_ANCHOR_ROLE,
            members: holderMembers
        });

        _initializeRbacs(rbacs);
    }

    /// @notice Forces the pause flag on so whenNotPaused branches can be tested.
    function pauseForTest() external {
        _pauseStorage().pause = true;
    }

    /// @notice Forces the pause flag off.
    function unpauseForTest() external {
        _pauseStorage().pause = false;
    }
}
