// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {AuditTypes} from "./AuditTypes.sol";
import {IProject} from "./IProject.sol";
import {ProjectInternal} from "./ProjectInternal.sol";

import {
    _PROJECT_SCHEMA_MANAGER_ROLE,
    _PROJECT_ALGORITHM_MANAGER_ROLE,
    _PROJECT_KEY_MANAGER_ROLE,
    _PROJECT_KEY_REVOKER_ROLE,
    _PROJECT_ANCHOR_ROLE,
    _PROJECT_EIP712_VERSION
} from "../constants/constants.sol";

/// @title CTB Audit Service V1
/// @notice External function layer for schema registry, algorithm registry, key registry and audit anchoring.
/// @dev This contract is intended to be used as an ISBE Diamond facet implementation.
abstract contract Project is IProject, ProjectInternal {
    /*//////////////////////////////////////////////////////////////
                            SCHEMA REGISTRY
    //////////////////////////////////////////////////////////////*/

    function registerSchema(
        bytes32 schemaId,
        bytes32 schemaVersion,
        bytes32 schemaHash,
        bytes32 eip712TypeHash
    ) external override whenNotPaused onlyRole(_PROJECT_SCHEMA_MANAGER_ROLE) {
        _registerSchema(schemaId, schemaVersion, schemaHash, eip712TypeHash);
    }

    function setSchemaEnabled(
        bytes32 schemaId,
        bytes32 schemaVersion,
        bool enabled
    ) external override whenNotPaused onlyRole(_PROJECT_SCHEMA_MANAGER_ROLE) {
        _setSchemaEnabled(schemaId, schemaVersion, enabled);
    }

    function getSchema(
        bytes32 schemaId,
        bytes32 schemaVersion
    ) external view override returns (AuditTypes.Schema memory schema) {
        return _getSchema(schemaId, schemaVersion);
    }

    /*//////////////////////////////////////////////////////////////
                          ALGORITHM REGISTRY
    //////////////////////////////////////////////////////////////*/

    function registerAlgorithm(
        bytes32 algorithmId,
        address verifier
    )
        external
        override
        whenNotPaused
        onlyRole(_PROJECT_ALGORITHM_MANAGER_ROLE)
    {
        _registerAlgorithm(algorithmId, verifier);
    }

    function setAlgorithmEnabled(
        bytes32 algorithmId,
        bool enabled
    )
        external
        override
        whenNotPaused
        onlyRole(_PROJECT_ALGORITHM_MANAGER_ROLE)
    {
        _setAlgorithmEnabled(algorithmId, enabled);
    }

    function getAlgorithm(
        bytes32 algorithmId
    ) external view override returns (AuditTypes.Algorithm memory algorithm) {
        return _getAlgorithm(algorithmId);
    }

    /*//////////////////////////////////////////////////////////////
                              KEY REGISTRY
    //////////////////////////////////////////////////////////////*/

    function registerKey(
        bytes32 keyId,
        bytes32 algorithmId,
        bytes calldata publicKey,
        bytes32 tenantId,
        uint64 expiresAt
    ) external override whenNotPaused onlyRole(_PROJECT_KEY_MANAGER_ROLE) {
        _registerKey(keyId, algorithmId, publicKey, tenantId, expiresAt);
    }

    function revokeKey(
        bytes32 keyId
    ) external override whenNotPaused onlyRole(_PROJECT_KEY_REVOKER_ROLE) {
        _revokeKey(keyId);
    }

    function getKey(
        bytes32 keyId
    ) external view override returns (AuditTypes.Key memory key) {
        return _getKey(keyId);
    }

    function isKeyActive(
        bytes32 keyId
    ) external view override returns (bool active) {
        return _isKeyActive(keyId);
    }

    function isKeyActiveAt(
        bytes32 keyId,
        uint64 timestamp
    ) external view override returns (bool active) {
        return _isKeyActiveAtExternal(keyId, timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                            AUDIT ANCHORING
    //////////////////////////////////////////////////////////////*/

    function anchor(
        AuditTypes.AuditEnvelope calldata envelope,
        AuditTypes.SignatureInput[] calldata signatures
    ) external override whenNotPaused onlyRole(_PROJECT_ANCHOR_ROLE) {
        _anchor(envelope, signatures);
    }

    function exists(
        bytes32 eventHash
    ) external view override returns (bool exists_) {
        return _exists(eventHash);
    }

    function getAnchor(
        bytes32 eventHash
    ) external view override returns (AuditTypes.Anchor memory anchor_) {
        return _getAnchor(eventHash);
    }

    function getSigners(
        bytes32 eventHash
    )
        external
        view
        override
        returns (AuditTypes.SignerRecord[] memory signers)
    {
        return _getSigners(eventHash);
    }

    function getSigner(
        bytes32 eventHash,
        bytes32 keyId
    ) external view override returns (AuditTypes.SignerRecord memory signer) {
        return _getSigner(eventHash, keyId);
    }

    function hasSigner(
        bytes32 eventHash,
        bytes32 keyId
    ) external view override returns (bool signed_) {
        return _hasSigner(eventHash, keyId);
    }

    function getSignerCount(
        bytes32 eventHash
    ) external view override returns (uint256 count) {
        return _getSignerCount(eventHash);
    }

    function verifySignature(
        AuditTypes.AuditEnvelope calldata envelope,
        AuditTypes.SignatureInput calldata signature
    ) external view override returns (bool valid) {
        return _verifySignature(envelope, signature);
    }

    function verifySignatures(
        AuditTypes.AuditEnvelope calldata envelope,
        AuditTypes.SignatureInput[] calldata signatures
    ) external view override returns (bool[] memory results) {
        return _verifySignatures(envelope, signatures);
    }

    function hashEnvelope(
        AuditTypes.AuditEnvelope calldata envelope
    ) external view override returns (bytes32 digest) {
        return _hashEnvelope(envelope);
    }

    /*//////////////////////////////////////////////////////////////
                                METADATA
    //////////////////////////////////////////////////////////////*/

    function eip712Domain()
        external
        view
        override
        returns (
            bytes1 fields,
            string memory name,
            string memory version_,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        )
    {
        return _eip712Domain();
    }

    function version() external pure override returns (string memory) {
        return _PROJECT_EIP712_VERSION;
    }

    /*//////////////////////////////////////////////////////////////
                            ISBE INTROSPECTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Declares the interfaces implemented by this project facet for ISBE introspection.
    function _implementedInterfaces()
        internal
        pure
        virtual
        override
        returns (bytes4[] memory interfaces_)
    {
        interfaces_ = new bytes4[](1);
        interfaces_[0] = type(IProject).interfaceId;
    }
}
