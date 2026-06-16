// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {Project} from "./Project.sol";
import {IEIP2535Introspection} from "@red-isbe/isbe-contracts/contracts/proxies/eip2535/interfaces/IEIP2535Introspection.sol";
import {_PROJECT_RESOLVER_KEY} from "../constants/constants.sol";

/// @title CTB Audit Service V1 Facet
/// @notice Diamond facet for CTB Audit Service V1.
contract ProjectFacet is Project, IEIP2535Introspection {
    function interfacesIntrospection()
        external
        pure
        returns (bytes4[] memory interfaces_)
    {
        return _implementedInterfaces();
    }

    function businessIdIntrospection()
        external
        pure
        override
        returns (bytes32 businessId_)
    {
        businessId_ = _PROJECT_RESOLVER_KEY;
    }

    function selectorsIntrospection()
        external
        pure
        override
        returns (bytes4[] memory selectors_)
    {
        uint256 selectorsLength = 23;
        selectors_ = new bytes4[](selectorsLength);

        selectors_[--selectorsLength] = this.registerSchema.selector;
        selectors_[--selectorsLength] = this.setSchemaEnabled.selector;
        selectors_[--selectorsLength] = this.getSchema.selector;
        selectors_[--selectorsLength] = this.registerAlgorithm.selector;
        selectors_[--selectorsLength] = this.setAlgorithmEnabled.selector;
        selectors_[--selectorsLength] = this.getAlgorithm.selector;
        selectors_[--selectorsLength] = this.registerKey.selector;
        selectors_[--selectorsLength] = this.revokeKey.selector;
        selectors_[--selectorsLength] = this.getKey.selector;
        selectors_[--selectorsLength] = this.isKeyActive.selector;
        selectors_[--selectorsLength] = this.isKeyActiveAt.selector;
        selectors_[--selectorsLength] = this.anchor.selector;
        selectors_[--selectorsLength] = this.exists.selector;
        selectors_[--selectorsLength] = this.getAnchor.selector;
        selectors_[--selectorsLength] = this.getSigners.selector;
        selectors_[--selectorsLength] = this.getSigner.selector;
        selectors_[--selectorsLength] = this.hasSigner.selector;
        selectors_[--selectorsLength] = this.getSignerCount.selector;
        selectors_[--selectorsLength] = this.verifySignature.selector;
        selectors_[--selectorsLength] = this.verifySignatures.selector;
        selectors_[--selectorsLength] = this.hashEnvelope.selector;
        selectors_[--selectorsLength] = this.eip712Domain.selector;
        selectors_[--selectorsLength] = this.version.selector;
    }
}