// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;
import {
    MessageHashUtils
} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {
    DidDocumentDetailedInternal
} from "@red-isbe/isbe-contracts/contracts/identity/didregistry/DidDocumentDetailedInternal.sol";
import {AuditTypes} from "./AuditTypes.sol";
import {IProject} from "./IProject.sol";
import {ISignatureVerifier} from "./ISignatureVerifier.sol";

import {
    _PROJECT_STORAGE_POSITION,
    _PROJECT_EIP712_NAME,
    _PROJECT_EIP712_VERSION
} from "../constants/constants.sol";

/// @title CTB Audit Service V1 Internal Logic
/// @notice Storage and internal logic for schemas, algorithms, keys and audit anchoring.
/// @dev Do not declare regular state variables in facets. All state lives in ProjectStorage.
abstract contract ProjectInternal is DidDocumentDetailedInternal {
    bytes32 internal constant _EIP712_DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );

    bytes32 internal constant _AUDIT_ENVELOPE_TYPEHASH =
        keccak256(
            "AuditEnvelope(bytes32 eventHash,bytes32 schemaId,bytes32 schemaVersion,bytes32 schemaHash,bytes32 eip712TypeHash,bytes32 tenantId,uint8 status,bytes32 nonce)"
        );

    struct ProjectStorage {
        mapping(bytes32 schemaId => mapping(bytes32 schemaVersion => AuditTypes.Schema)) schemas;
        mapping(bytes32 algorithmId => AuditTypes.Algorithm) algorithms;
        mapping(bytes32 keyId => AuditTypes.Key) keys;
        mapping(bytes32 eventHash => AuditTypes.Anchor) anchors;
        mapping(bytes32 eventHash => AuditTypes.SignerRecord[]) signersByEventHash;
        // Stores (index + 1) into signersByEventHash[eventHash] so that the
        // zero value unambiguously means "no record". Lets _getSigner stay O(1)
        // without duplicating the SignerRecord struct or a separate bool flag.
        mapping(bytes32 eventHash => mapping(bytes32 keyId => uint256)) signerIndexPlusOne;
    }

    /*//////////////////////////////////////////////////////////////
                            SCHEMA REGISTRY
    //////////////////////////////////////////////////////////////*/

    function _registerSchema(
        bytes32 schemaId,
        bytes32 schemaVersion,
        bytes32 schemaHash,
        bytes32 eip712TypeHash
    ) internal virtual {
        if (schemaId == bytes32(0)) revert IProject.InvalidSchemaId();
        if (schemaVersion == bytes32(0)) revert IProject.InvalidSchemaVersion();
        if (schemaHash == bytes32(0)) revert IProject.InvalidSchemaHash();
        if (eip712TypeHash == bytes32(0)) {
            revert IProject.InvalidEip712TypeHash();
        }

        ProjectStorage storage $ = _projectStorage();

        if (_schemaExists($, schemaId, schemaVersion)) {
            revert IProject.SchemaAlreadyRegistered(schemaId, schemaVersion);
        }

        $.schemas[schemaId][schemaVersion] = AuditTypes.Schema({
            schemaId: schemaId,
            schemaVersion: schemaVersion,
            schemaHash: schemaHash,
            eip712TypeHash: eip712TypeHash,
            enabled: true
        });

        emit IProject.SchemaRegistered(
            schemaId,
            schemaVersion,
            schemaHash,
            eip712TypeHash
        );
    }

    function _setSchemaEnabled(
        bytes32 schemaId,
        bytes32 schemaVersion,
        bool enabled
    ) internal virtual {
        ProjectStorage storage $ = _projectStorage();

        if (!_schemaExists($, schemaId, schemaVersion)) {
            revert IProject.SchemaNotRegistered(schemaId, schemaVersion);
        }

        $.schemas[schemaId][schemaVersion].enabled = enabled;

        emit IProject.SchemaEnabledSet(schemaId, schemaVersion, enabled);
    }

    function _getSchema(
        bytes32 schemaId,
        bytes32 schemaVersion
    ) internal view virtual returns (AuditTypes.Schema memory schema) {
        ProjectStorage storage $ = _projectStorage();

        if (!_schemaExists($, schemaId, schemaVersion)) {
            revert IProject.SchemaNotRegistered(schemaId, schemaVersion);
        }

        return $.schemas[schemaId][schemaVersion];
    }

    /*//////////////////////////////////////////////////////////////
                          ALGORITHM REGISTRY
    //////////////////////////////////////////////////////////////*/

    function _registerAlgorithm(
        bytes32 algorithmId,
        address verifier
    ) internal virtual {
        if (algorithmId == bytes32(0)) revert IProject.InvalidAlgorithmId();
        if (verifier == address(0)) revert IProject.InvalidVerifierAddress();
        if (verifier.code.length == 0) revert IProject.InvalidVerifierAddress();

        ProjectStorage storage $ = _projectStorage();

        if (_algorithmExists($, algorithmId)) {
            revert IProject.AlgorithmAlreadyRegistered(algorithmId);
        }

        $.algorithms[algorithmId] = AuditTypes.Algorithm({
            algorithmId: algorithmId,
            verifier: verifier,
            enabled: true
        });

        emit IProject.AlgorithmRegistered(algorithmId, verifier);
    }

    function _setAlgorithmEnabled(
        bytes32 algorithmId,
        bool enabled
    ) internal virtual {
        ProjectStorage storage $ = _projectStorage();

        if (!_algorithmExists($, algorithmId)) {
            revert IProject.AlgorithmNotRegistered(algorithmId);
        }

        $.algorithms[algorithmId].enabled = enabled;

        emit IProject.AlgorithmEnabledSet(algorithmId, enabled);
    }

    function _getAlgorithm(
        bytes32 algorithmId
    ) internal view virtual returns (AuditTypes.Algorithm memory algorithm) {
        ProjectStorage storage $ = _projectStorage();

        if (!_algorithmExists($, algorithmId)) {
            revert IProject.AlgorithmNotRegistered(algorithmId);
        }

        return $.algorithms[algorithmId];
    }

    /*//////////////////////////////////////////////////////////////
                              KEY REGISTRY
    //////////////////////////////////////////////////////////////*/

    function _registerKey(
        bytes32 keyId,
        bytes32 algorithmId,
        bytes calldata publicKey,
        bytes32 tenantId,
        uint64 expiresAt
    ) internal virtual {
        if (keyId == bytes32(0)) revert IProject.InvalidKeyId();
        if (algorithmId == bytes32(0)) revert IProject.InvalidAlgorithmId();
        if (publicKey.length == 0) revert IProject.InvalidPublicKey();
        if (tenantId == bytes32(0)) revert IProject.InvalidTenantId();

        ProjectStorage storage $ = _projectStorage();

        if (_keyExists($, keyId)) {
            revert IProject.KeyAlreadyRegistered(keyId);
        }

        if (!_algorithmExists($, algorithmId)) {
            revert IProject.AlgorithmNotRegistered(algorithmId);
        }

        AuditTypes.Algorithm storage algorithm = $.algorithms[algorithmId];

        if (!algorithm.enabled) {
            revert IProject.AlgorithmDisabled(algorithmId);
        }

        uint64 timestamp = _blockTimestamp64();

        if (expiresAt != 0 && expiresAt <= timestamp) {
            revert IProject.InvalidExpiresAt(keyId, expiresAt);
        }

        $.keys[keyId] = AuditTypes.Key({
            keyId: keyId,
            algorithmId: algorithmId,
            publicKey: publicKey,
            tenantId: tenantId,
            registeredAt: timestamp,
            expiresAt: expiresAt,
            revokedAt: 0,
            active: true
        });

        emit IProject.KeyRegistered(
            keyId,
            algorithmId,
            tenantId,
            timestamp,
            expiresAt
        );
    }

    function _revokeKey(bytes32 keyId) internal virtual {
        ProjectStorage storage $ = _projectStorage();

        if (!_keyExists($, keyId)) {
            revert IProject.KeyNotRegistered(keyId);
        }

        AuditTypes.Key storage key = $.keys[keyId];

        uint64 timestamp = _blockTimestamp64();

        if (!_isKeyActiveAt($, keyId, timestamp)) {
            revert IProject.KeyNotActive(keyId);
        }

        key.active = false;
        key.revokedAt = timestamp;

        emit IProject.KeyRevoked(keyId, timestamp);
    }

    function _getKey(
        bytes32 keyId
    ) internal view virtual returns (AuditTypes.Key memory key) {
        ProjectStorage storage $ = _projectStorage();

        if (!_keyExists($, keyId)) {
            revert IProject.KeyNotRegistered(keyId);
        }

        return $.keys[keyId];
    }

    function _isKeyActive(
        bytes32 keyId
    ) internal view virtual returns (bool active) {
        return _isKeyActiveAt(_projectStorage(), keyId, _blockTimestamp64());
    }

    function _isKeyActiveAtExternal(
        bytes32 keyId,
        uint64 timestamp
    ) internal view virtual returns (bool active) {
        return _isKeyActiveAt(_projectStorage(), keyId, timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                            AUDIT ANCHORING
    //////////////////////////////////////////////////////////////*/

    function _anchor(
        AuditTypes.AuditEnvelope calldata envelope,
        AuditTypes.SignatureInput[] calldata signatures
    ) internal virtual {
        _requireValidEnvelope(envelope);

        if (signatures.length == 0) {
            revert IProject.NoSignaturesProvided();
        }

        ProjectStorage storage $ = _projectStorage();

        if (_exists($, envelope.eventHash)) {
            revert IProject.EventAlreadyAnchored(envelope.eventHash);
        }

        _requireEnabledSchemaForEnvelope($, envelope);

        bytes32 digest = _hashEnvelope(envelope);
        uint64 timestamp = _blockTimestamp64();

        for (uint256 i = 0; i < signatures.length; i++) {
            _recordVerifiedSigner(
                $,
                envelope,
                signatures[i],
                digest,
                timestamp
            );
        }

        $.anchors[envelope.eventHash] = AuditTypes.Anchor({
            eventHash: envelope.eventHash,
            digest: digest,
            schemaId: envelope.schemaId,
            schemaVersion: envelope.schemaVersion,
            tenantId: envelope.tenantId,
            status: envelope.status,
            anchoredAt: timestamp,
            signerCount: uint32(signatures.length)
        });

        emit IProject.AuditAnchored(
            envelope.eventHash,
            envelope.tenantId,
            envelope.schemaId,
            envelope.schemaVersion,
            digest,
            envelope.status,
            uint32(signatures.length),
            timestamp
        );
    }

    function _exists(
        bytes32 eventHash
    ) internal view virtual returns (bool exists_) {
        return _exists(_projectStorage(), eventHash);
    }

    function _getAnchor(
        bytes32 eventHash
    ) internal view virtual returns (AuditTypes.Anchor memory anchor_) {
        ProjectStorage storage $ = _projectStorage();

        if (!_exists($, eventHash)) {
            revert IProject.EventNotAnchored(eventHash);
        }

        return $.anchors[eventHash];
    }

    function _getSigners(
        bytes32 eventHash
    ) internal view virtual returns (AuditTypes.SignerRecord[] memory signers) {
        ProjectStorage storage $ = _projectStorage();

        if (!_exists($, eventHash)) {
            revert IProject.EventNotAnchored(eventHash);
        }

        return $.signersByEventHash[eventHash];
    }

    function _getSigner(
        bytes32 eventHash,
        bytes32 keyId
    ) internal view virtual returns (AuditTypes.SignerRecord memory signer) {
        ProjectStorage storage $ = _projectStorage();

        uint256 idx = $.signerIndexPlusOne[eventHash][keyId];
        if (idx == 0) {
            revert IProject.SignerNotFound(eventHash, keyId);
        }

        return $.signersByEventHash[eventHash][idx - 1];
    }

    function _hasSigner(
        bytes32 eventHash,
        bytes32 keyId
    ) internal view virtual returns (bool signed_) {
        return _projectStorage().signerIndexPlusOne[eventHash][keyId] != 0;
    }

    function _getSignerCount(
        bytes32 eventHash
    ) internal view virtual returns (uint256 count) {
        return _projectStorage().signersByEventHash[eventHash].length;
    }

    function _verifySignature(
        AuditTypes.AuditEnvelope calldata envelope,
        AuditTypes.SignatureInput calldata signature
    ) internal view virtual returns (bool valid) {
        if (!_isEnvelopeWellFormed(envelope)) {
            return false;
        }

        ProjectStorage storage $ = _projectStorage();

        if (!_isSchemaEnabledForEnvelope($, envelope)) {
            return false;
        }

        return
            _verifySignatureAgainstDigest(
                $,
                envelope.tenantId,
                signature,
                _hashEnvelope(envelope)
            );
    }

    function _verifySignatures(
        AuditTypes.AuditEnvelope calldata envelope,
        AuditTypes.SignatureInput[] calldata signatures
    ) internal view virtual returns (bool[] memory results) {
        results = new bool[](signatures.length);

        if (!_isEnvelopeWellFormed(envelope)) {
            return results;
        }

        ProjectStorage storage $ = _projectStorage();

        if (!_isSchemaEnabledForEnvelope($, envelope)) {
            return results;
        }

        bytes32 digest = _hashEnvelope(envelope);

        for (uint256 i = 0; i < signatures.length; i++) {
            results[i] = _verifySignatureAgainstDigest(
                $,
                envelope.tenantId,
                signatures[i],
                digest
            );
        }
    }

    function _hashEnvelope(
        AuditTypes.AuditEnvelope calldata envelope
    ) internal view virtual returns (bytes32 digest) {
        bytes32 structHash = keccak256(
            abi.encode(
                _AUDIT_ENVELOPE_TYPEHASH,
                envelope.eventHash,
                envelope.schemaId,
                envelope.schemaVersion,
                envelope.schemaHash,
                envelope.eip712TypeHash,
                envelope.tenantId,
                envelope.status,
                envelope.nonce
            )
        );

        return
            MessageHashUtils.toTypedDataHash(_domainSeparatorV4(), structHash);
    }

    function _eip712Domain()
        internal
        view
        virtual
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
        fields = 0x0f;
        name = _PROJECT_EIP712_NAME;
        version_ = _PROJECT_EIP712_VERSION;
        chainId = block.chainid;
        verifyingContract = address(this);
        salt = bytes32(0);
        extensions = new uint256[](0);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _recordVerifiedSigner(
        ProjectStorage storage $,
        AuditTypes.AuditEnvelope calldata envelope,
        AuditTypes.SignatureInput calldata signature,
        bytes32 digest,
        uint64 timestamp
    ) internal virtual {
        if (signature.keyId == bytes32(0)) {
            revert IProject.InvalidKeyId();
        }

        if ($.signerIndexPlusOne[envelope.eventHash][signature.keyId] != 0) {
            revert IProject.DuplicateSigner(
                envelope.eventHash,
                signature.keyId
            );
        }

        if (!_keyExists($, signature.keyId)) {
            revert IProject.KeyNotRegistered(signature.keyId);
        }

        AuditTypes.Key storage key = $.keys[signature.keyId];

        if (!_isKeyActiveAt($, signature.keyId, timestamp)) {
            revert IProject.KeyNotActive(signature.keyId);
        }

        if (key.tenantId != envelope.tenantId) {
            revert IProject.KeyTenantMismatch(
                signature.keyId,
                envelope.tenantId,
                key.tenantId
            );
        }

        if (!_algorithmExists($, key.algorithmId)) {
            revert IProject.AlgorithmNotRegistered(key.algorithmId);
        }

        AuditTypes.Algorithm storage algorithm = $.algorithms[key.algorithmId];

        if (!algorithm.enabled) {
            revert IProject.AlgorithmDisabled(key.algorithmId);
        }

        if (
            !_callVerifier(
                algorithm.verifier,
                digest,
                signature.signature,
                key.publicKey
            )
        ) {
            revert IProject.InvalidSignature(signature.keyId);
        }

        bytes32 signerId = keccak256(
            abi.encode(envelope.eventHash, signature.keyId)
        );

        AuditTypes.SignerRecord memory signer = AuditTypes.SignerRecord({
            signerId: signerId,
            keyId: signature.keyId,
            algorithmId: key.algorithmId,
            signatureCommitment: keccak256(signature.signature),
            signedAt: timestamp
        });

        $.signersByEventHash[envelope.eventHash].push(signer);
        $.signerIndexPlusOne[envelope.eventHash][signature.keyId] = $
            .signersByEventHash[envelope.eventHash]
            .length;

        emit IProject.AuditSignerRecorded(
            envelope.eventHash,
            signerId,
            signature.keyId,
            key.algorithmId,
            signer.signatureCommitment,
            timestamp
        );
    }

    function _verifySignatureAgainstDigest(
        ProjectStorage storage $,
        bytes32 tenantId,
        AuditTypes.SignatureInput calldata signature,
        bytes32 digest
    ) internal view virtual returns (bool valid) {
        if (signature.keyId == bytes32(0)) {
            return false;
        }

        if (!_keyExists($, signature.keyId)) {
            return false;
        }

        if (!_isKeyActiveAt($, signature.keyId, _blockTimestamp64())) {
            return false;
        }

        AuditTypes.Key storage key = $.keys[signature.keyId];

        if (key.tenantId != tenantId) {
            return false;
        }

        if (!_algorithmExists($, key.algorithmId)) {
            return false;
        }

        AuditTypes.Algorithm storage algorithm = $.algorithms[key.algorithmId];

        if (!algorithm.enabled) {
            return false;
        }

        return
            _callVerifier(
                algorithm.verifier,
                digest,
                signature.signature,
                key.publicKey
            );
    }

    function _requireValidEnvelope(
        AuditTypes.AuditEnvelope calldata envelope
    ) internal pure virtual {
        if (envelope.eventHash == bytes32(0))
            revert IProject.InvalidEventHash();
        if (envelope.schemaId == bytes32(0)) revert IProject.InvalidSchemaId();
        if (envelope.schemaVersion == bytes32(0)) {
            revert IProject.InvalidSchemaVersion();
        }
        if (envelope.schemaHash == bytes32(0))
            revert IProject.InvalidSchemaHash();
        if (envelope.eip712TypeHash == bytes32(0)) {
            revert IProject.InvalidEip712TypeHash();
        }
        if (envelope.tenantId == bytes32(0)) revert IProject.InvalidTenantId();
        if (envelope.nonce == bytes32(0)) revert IProject.InvalidNonce();
    }

    function _isEnvelopeWellFormed(
        AuditTypes.AuditEnvelope calldata envelope
    ) internal pure virtual returns (bool valid) {
        return (envelope.eventHash != bytes32(0) &&
            envelope.schemaId != bytes32(0) &&
            envelope.schemaVersion != bytes32(0) &&
            envelope.schemaHash != bytes32(0) &&
            envelope.eip712TypeHash != bytes32(0) &&
            envelope.tenantId != bytes32(0) &&
            envelope.nonce != bytes32(0));
    }

    function _requireEnabledSchemaForEnvelope(
        ProjectStorage storage $,
        AuditTypes.AuditEnvelope calldata envelope
    ) internal view virtual {
        if (!_schemaExists($, envelope.schemaId, envelope.schemaVersion)) {
            revert IProject.SchemaNotRegistered(
                envelope.schemaId,
                envelope.schemaVersion
            );
        }

        AuditTypes.Schema storage schema = $.schemas[envelope.schemaId][
            envelope.schemaVersion
        ];

        if (!schema.enabled) {
            revert IProject.SchemaDisabled(
                envelope.schemaId,
                envelope.schemaVersion
            );
        }

        if (schema.schemaHash != envelope.schemaHash) {
            revert IProject.SchemaHashMismatch(
                envelope.schemaId,
                envelope.schemaVersion
            );
        }

        if (schema.eip712TypeHash != envelope.eip712TypeHash) {
            revert IProject.Eip712TypeHashMismatch(
                envelope.schemaId,
                envelope.schemaVersion
            );
        }
    }

    function _schemaExists(
        ProjectStorage storage $,
        bytes32 schemaId,
        bytes32 schemaVersion
    ) internal view virtual returns (bool exists_) {
        return $.schemas[schemaId][schemaVersion].schemaHash != bytes32(0);
    }

    function _isSchemaEnabledForEnvelope(
        ProjectStorage storage $,
        AuditTypes.AuditEnvelope calldata envelope
    ) internal view virtual returns (bool enabled) {
        if (!_schemaExists($, envelope.schemaId, envelope.schemaVersion)) {
            return false;
        }

        AuditTypes.Schema storage schema = $.schemas[envelope.schemaId][
            envelope.schemaVersion
        ];

        return (schema.enabled &&
            schema.schemaHash == envelope.schemaHash &&
            schema.eip712TypeHash == envelope.eip712TypeHash);
    }

    function _algorithmExists(
        ProjectStorage storage $,
        bytes32 algorithmId
    ) internal view virtual returns (bool exists_) {
        return $.algorithms[algorithmId].verifier != address(0);
    }

    function _keyExists(
        ProjectStorage storage $,
        bytes32 keyId
    ) internal view virtual returns (bool exists_) {
        return $.keys[keyId].keyId != bytes32(0);
    }

    function _exists(
        ProjectStorage storage $,
        bytes32 eventHash
    ) internal view virtual returns (bool exists_) {
        return $.anchors[eventHash].eventHash != bytes32(0);
    }

    // Activeness is derived purely from timestamps so historical signatures
    // remain auditable: a revoked key must still report active for timestamps
    // before its revocation. The Key.active boolean is informational only and
    // is intentionally NOT consulted here — registeredAt/revokedAt/expiresAt
    // are authoritative.
    function _isKeyActiveAt(
        ProjectStorage storage $,
        bytes32 keyId,
        uint64 timestamp
    ) internal view virtual returns (bool active) {
        if (!_keyExists($, keyId)) {
            return false;
        }

        AuditTypes.Key storage key = $.keys[keyId];

        if (key.registeredAt == 0 || key.registeredAt > timestamp) {
            return false;
        }

        if (key.revokedAt != 0 && key.revokedAt <= timestamp) {
            return false;
        }

        if (key.expiresAt != 0 && key.expiresAt <= timestamp) {
            return false;
        }

        return true;
    }

    function _callVerifier(
        address verifier,
        bytes32 digest,
        bytes calldata signature,
        bytes memory publicKey
    ) internal view virtual returns (bool valid) {
        if (verifier == address(0)) {
            return false;
        }

        try
            ISignatureVerifier(verifier).verify(digest, signature, publicKey)
        returns (bool result) {
            return result;
        } catch {
            return false;
        }
    }

    function _domainSeparatorV4() internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _EIP712_DOMAIN_TYPEHASH,
                    keccak256(bytes(_PROJECT_EIP712_NAME)),
                    keccak256(bytes(_PROJECT_EIP712_VERSION)),
                    block.chainid,
                    address(this)
                )
            );
    }

    function _blockTimestamp64() internal view virtual returns (uint64) {
        return uint64(_blockTimestamp());
    }

    function _projectStorage()
        internal
        pure
        returns (ProjectStorage storage storage_)
    {
        bytes32 position = _PROJECT_STORAGE_POSITION;

        // slither-disable-start assembly
        // solhint-disable-next-line no-inline-assembly
        assembly {
            storage_.slot := position
        }
        // slither-disable-end assembly
    }
}
