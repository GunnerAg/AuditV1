// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {ECDSA} from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import {
    DidDocumentDetailedInternal
} from '@red-isbe/isbe-contracts/contracts/identity/didregistry/DidDocumentDetailedInternal.sol';
import {AuditTypes} from './AuditTypes.sol';
import {IAuditService} from './IAuditService.sol';
import {
    _AUDIT_SERVICE_STORAGE_POSITION,
    _AUDIT_SERVICE_EIP712_NAME,
    _AUDIT_SERVICE_EIP712_VERSION,
    _AUDIT_SERVICE_ECDSA_ALGORITHM_ID
} from '../constants/constants.sol';

/// @title CTB Audit Service V1 Internal Logic
/// @notice Storage and internal logic for schemas, algorithms, keys and audit anchoring.
/// @dev Do not declare regular state variables in facets. All state lives in AuditServiceStorage.
abstract contract AuditServiceInternal is DidDocumentDetailedInternal {
    bytes32 internal constant _EIP712_DOMAIN_TYPEHASH =
        keccak256(
            'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
        );

    bytes32 internal constant _AUDIT_ENVELOPE_TYPEHASH =
        keccak256(
            'AuditEnvelope(bytes32 eventHash,bytes32 schemaId,bytes32 schemaVersion,bytes32 schemaHash,bytes32 eip712TypeHash,bytes32 tenantId,uint8 status,bytes32 nonce)'
        );

    struct AuditServiceStorage {
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
        if (schemaId == bytes32(0)) revert IAuditService.InvalidSchemaId();
        if (schemaVersion == bytes32(0)) revert IAuditService.InvalidSchemaVersion();
        if (schemaHash == bytes32(0)) revert IAuditService.InvalidSchemaHash();
        if (eip712TypeHash == bytes32(0)) revert IAuditService.InvalidEip712TypeHash();

        AuditServiceStorage storage $ = _auditServiceStorage();

        if (_schemaExists($, schemaId, schemaVersion)) {
            revert IAuditService.SchemaAlreadyRegistered(schemaId, schemaVersion);
        }

        $.schemas[schemaId][schemaVersion] = AuditTypes.Schema({
            schemaId: schemaId,
            schemaVersion: schemaVersion,
            schemaHash: schemaHash,
            eip712TypeHash: eip712TypeHash,
            enabled: true
        });

        emit IAuditService.SchemaRegistered(schemaId, schemaVersion, schemaHash, eip712TypeHash);
    }

    function _setSchemaEnabled(
        bytes32 schemaId,
        bytes32 schemaVersion,
        bool enabled
    ) internal virtual {
        AuditServiceStorage storage $ = _auditServiceStorage();

        if (!_schemaExists($, schemaId, schemaVersion)) {
            revert IAuditService.SchemaNotRegistered(schemaId, schemaVersion);
        }

        $.schemas[schemaId][schemaVersion].enabled = enabled;

        emit IAuditService.SchemaEnabledSet(schemaId, schemaVersion, enabled);
    }

    function _getSchema(
        bytes32 schemaId,
        bytes32 schemaVersion
    ) internal view virtual returns (AuditTypes.Schema memory) {
        AuditServiceStorage storage $ = _auditServiceStorage();

        if (!_schemaExists($, schemaId, schemaVersion)) {
            revert IAuditService.SchemaNotRegistered(schemaId, schemaVersion);
        }

        return $.schemas[schemaId][schemaVersion];
    }

    /*//////////////////////////////////////////////////////////////
                          ALGORITHM REGISTRY
    //////////////////////////////////////////////////////////////*/

    function _registerAlgorithm(bytes32 algorithmId) internal virtual {
        if (algorithmId == bytes32(0)) revert IAuditService.InvalidAlgorithmId();
        if (!_isSupportedAlgorithm(algorithmId)) {
            revert IAuditService.UnsupportedAlgorithm(algorithmId);
        }

        AuditServiceStorage storage $ = _auditServiceStorage();

        if (_algorithmExists($, algorithmId)) {
            revert IAuditService.AlgorithmAlreadyRegistered(algorithmId);
        }

        $.algorithms[algorithmId] = AuditTypes.Algorithm({
            algorithmId: algorithmId,
            enabled: true
        });

        emit IAuditService.AlgorithmRegistered(algorithmId);
    }

    function _setAlgorithmEnabled(bytes32 algorithmId, bool enabled) internal virtual {
        AuditServiceStorage storage $ = _auditServiceStorage();

        if (!_algorithmExists($, algorithmId)) {
            revert IAuditService.AlgorithmNotRegistered(algorithmId);
        }

        $.algorithms[algorithmId].enabled = enabled;

        emit IAuditService.AlgorithmEnabledSet(algorithmId, enabled);
    }

    function _getAlgorithm(
        bytes32 algorithmId
    ) internal view virtual returns (AuditTypes.Algorithm memory) {
        AuditServiceStorage storage $ = _auditServiceStorage();

        if (!_algorithmExists($, algorithmId)) {
            revert IAuditService.AlgorithmNotRegistered(algorithmId);
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
        if (keyId == bytes32(0)) revert IAuditService.InvalidKeyId();
        if (algorithmId == bytes32(0)) revert IAuditService.InvalidAlgorithmId();
        if (publicKey.length == 0) revert IAuditService.InvalidPublicKey();
        if (tenantId == bytes32(0)) revert IAuditService.InvalidTenantId();

        AuditServiceStorage storage $ = _auditServiceStorage();

        if (_keyExists($, keyId)) revert IAuditService.KeyAlreadyRegistered(keyId);
        if (!_algorithmExists($, algorithmId)) revert IAuditService.AlgorithmNotRegistered(algorithmId);
        if (!$.algorithms[algorithmId].enabled) revert IAuditService.AlgorithmDisabled(algorithmId);

        uint64 timestamp = _blockTimestamp64();

        if (expiresAt != 0 && expiresAt <= timestamp) {
            revert IAuditService.InvalidExpiresAt(keyId, expiresAt);
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

        emit IAuditService.KeyRegistered(keyId, algorithmId, tenantId, timestamp, expiresAt);
    }

    function _revokeKey(bytes32 keyId) internal virtual {
        AuditServiceStorage storage $ = _auditServiceStorage();

        if (!_keyExists($, keyId)) revert IAuditService.KeyNotRegistered(keyId);

        uint64 timestamp = _blockTimestamp64();

        if (!_isKeyActiveAt($, keyId, timestamp)) revert IAuditService.KeyNotActive(keyId);

        $.keys[keyId].active = false;
        $.keys[keyId].revokedAt = timestamp;

        emit IAuditService.KeyRevoked(keyId, timestamp);
    }

    function _getKey(bytes32 keyId) internal view virtual returns (AuditTypes.Key memory) {
        AuditServiceStorage storage $ = _auditServiceStorage();

        if (!_keyExists($, keyId)) revert IAuditService.KeyNotRegistered(keyId);

        return $.keys[keyId];
    }

    function _isKeyActive(bytes32 keyId) internal view virtual returns (bool) {
        return _isKeyActiveAt(_auditServiceStorage(), keyId, _blockTimestamp64());
    }

    function _isKeyActiveAtExternal(bytes32 keyId, uint64 timestamp) internal view virtual returns (bool) {
        return _isKeyActiveAt(_auditServiceStorage(), keyId, timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                            AUDIT ANCHORING
    //////////////////////////////////////////////////////////////*/

    function _anchor(
        AuditTypes.AuditEnvelope calldata envelope,
        AuditTypes.SignatureInput[] calldata signatures
    ) internal virtual {
        _requireValidEnvelope(envelope);

        if (signatures.length == 0) revert IAuditService.NoSignaturesProvided();

        AuditServiceStorage storage $ = _auditServiceStorage();

        if (_exists($, envelope.eventHash)) {
            revert IAuditService.EventAlreadyAnchored(envelope.eventHash);
        }

        _requireEnabledSchemaForEnvelope($, envelope);

        bytes32 digest = _hashEnvelope(envelope);
        uint64 timestamp = _blockTimestamp64();

        for (uint256 i = 0; i < signatures.length; i++) {
            _recordVerifiedSigner($, envelope, signatures[i], digest, timestamp);
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

        emit IAuditService.AuditAnchored(
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

    function _exists(bytes32 eventHash) internal view virtual returns (bool) {
        return _exists(_auditServiceStorage(), eventHash);
    }

    function _getAnchor(bytes32 eventHash) internal view virtual returns (AuditTypes.Anchor memory) {
        AuditServiceStorage storage $ = _auditServiceStorage();

        if (!_exists($, eventHash)) revert IAuditService.EventNotAnchored(eventHash);

        return $.anchors[eventHash];
    }

    function _getSigners(
        bytes32 eventHash
    ) internal view virtual returns (AuditTypes.SignerRecord[] memory) {
        AuditServiceStorage storage $ = _auditServiceStorage();

        if (!_exists($, eventHash)) revert IAuditService.EventNotAnchored(eventHash);

        return $.signersByEventHash[eventHash];
    }

    function _getSigner(
        bytes32 eventHash,
        bytes32 keyId
    ) internal view virtual returns (AuditTypes.SignerRecord memory) {
        AuditServiceStorage storage $ = _auditServiceStorage();

        uint256 idx = $.signerIndexPlusOne[eventHash][keyId];
        if (idx == 0) revert IAuditService.SignerNotFound(eventHash, keyId);

        return $.signersByEventHash[eventHash][idx - 1];
    }

    function _hasSigner(bytes32 eventHash, bytes32 keyId) internal view virtual returns (bool) {
        return _auditServiceStorage().signerIndexPlusOne[eventHash][keyId] != 0;
    }

    function _getSignerCount(bytes32 eventHash) internal view virtual returns (uint256) {
        return _auditServiceStorage().signersByEventHash[eventHash].length;
    }

    function _verifySignature(
        AuditTypes.AuditEnvelope calldata envelope,
        AuditTypes.SignatureInput calldata signature
    ) internal view virtual returns (bool) {
        if (!_isEnvelopeWellFormed(envelope)) return false;

        AuditServiceStorage storage $ = _auditServiceStorage();

        if (!_isSchemaEnabledForEnvelope($, envelope)) return false;

        return _verifySignatureAgainstDigest($, envelope.tenantId, signature, _hashEnvelope(envelope));
    }

    function _verifySignatures(
        AuditTypes.AuditEnvelope calldata envelope,
        AuditTypes.SignatureInput[] calldata signatures
    ) internal view virtual returns (bool[] memory results) {
        results = new bool[](signatures.length);

        if (!_isEnvelopeWellFormed(envelope)) return results;

        AuditServiceStorage storage $ = _auditServiceStorage();

        if (!_isSchemaEnabledForEnvelope($, envelope)) return results;

        bytes32 digest = _hashEnvelope(envelope);

        for (uint256 i = 0; i < signatures.length; i++) {
            results[i] = _verifySignatureAgainstDigest($, envelope.tenantId, signatures[i], digest);
        }
    }

    function _hashEnvelope(
        AuditTypes.AuditEnvelope calldata envelope
    ) internal view virtual returns (bytes32) {
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

        return MessageHashUtils.toTypedDataHash(_domainSeparatorV4(), structHash);
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
        name = _AUDIT_SERVICE_EIP712_NAME;
        version_ = _AUDIT_SERVICE_EIP712_VERSION;
        chainId = block.chainid;
        verifyingContract = address(this);
        salt = bytes32(0);
        extensions = new uint256[](0);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _recordVerifiedSigner(
        AuditServiceStorage storage $,
        AuditTypes.AuditEnvelope calldata envelope,
        AuditTypes.SignatureInput calldata signature,
        bytes32 digest,
        uint64 timestamp
    ) internal virtual {
        if (signature.keyId == bytes32(0)) revert IAuditService.InvalidKeyId();

        if ($.signerIndexPlusOne[envelope.eventHash][signature.keyId] != 0) {
            revert IAuditService.DuplicateSigner(envelope.eventHash, signature.keyId);
        }

        if (!_keyExists($, signature.keyId)) revert IAuditService.KeyNotRegistered(signature.keyId);

        AuditTypes.Key storage key = $.keys[signature.keyId];

        if (!_isKeyActiveAt($, signature.keyId, timestamp)) revert IAuditService.KeyNotActive(signature.keyId);

        if (key.tenantId != envelope.tenantId) {
            revert IAuditService.KeyTenantMismatch(signature.keyId, envelope.tenantId, key.tenantId);
        }

        if (!_algorithmExists($, key.algorithmId)) revert IAuditService.AlgorithmNotRegistered(key.algorithmId);
        if (!$.algorithms[key.algorithmId].enabled) revert IAuditService.AlgorithmDisabled(key.algorithmId);

        if (!_verifyNative(key.algorithmId, digest, signature.signature, key.publicKey)) {
            revert IAuditService.InvalidSignature(signature.keyId);
        }

        bytes32 signerId = keccak256(abi.encode(envelope.eventHash, signature.keyId));

        AuditTypes.SignerRecord memory signer = AuditTypes.SignerRecord({
            signerId: signerId,
            keyId: signature.keyId,
            algorithmId: key.algorithmId,
            signatureCommitment: keccak256(signature.signature),
            signedAt: timestamp
        });

        $.signersByEventHash[envelope.eventHash].push(signer);
        $.signerIndexPlusOne[envelope.eventHash][signature.keyId] =
            $.signersByEventHash[envelope.eventHash].length;

        emit IAuditService.AuditSignerRecorded(
            envelope.eventHash,
            signerId,
            signature.keyId,
            key.algorithmId,
            signer.signatureCommitment,
            timestamp
        );
    }

    function _verifySignatureAgainstDigest(
        AuditServiceStorage storage $,
        bytes32 tenantId,
        AuditTypes.SignatureInput calldata signature,
        bytes32 digest
    ) internal view virtual returns (bool) {
        if (signature.keyId == bytes32(0)) return false;
        if (!_keyExists($, signature.keyId)) return false;
        if (!_isKeyActiveAt($, signature.keyId, _blockTimestamp64())) return false;

        AuditTypes.Key storage key = $.keys[signature.keyId];

        if (key.tenantId != tenantId) return false;
        if (!_algorithmExists($, key.algorithmId)) return false;
        if (!$.algorithms[key.algorithmId].enabled) return false;

        return _verifyNative(key.algorithmId, digest, signature.signature, key.publicKey);
    }

    /// @dev Dispatches signature verification to the appropriate native implementation.
    ///      New algorithms can be added in future facet upgrades by extending this function.
    function _verifyNative(
        bytes32 algorithmId,
        bytes32 digest,
        bytes calldata signature,
        bytes memory publicKey
    ) internal pure virtual returns (bool) {
        if (algorithmId == _AUDIT_SERVICE_ECDSA_ALGORITHM_ID) {
            return _verifyEcdsa(digest, signature, publicKey);
        }
        return false;
    }

    /// @dev ECDSA secp256k1 verification.
    ///      publicKey encoding: abi.encode(address expectedSigner) — exactly 32 bytes.
    function _verifyEcdsa(
        bytes32 digest,
        bytes calldata signature,
        bytes memory publicKey
    ) internal pure virtual returns (bool) {
        if (digest == bytes32(0)) return false;
        if (publicKey.length != 32) return false;

        address expectedSigner = abi.decode(publicKey, (address));
        if (expectedSigner == address(0)) return false;

        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signature);

        return err == ECDSA.RecoverError.NoError && recovered == expectedSigner;
    }

    /// @dev Returns true only for algorithm IDs natively supported by this contract version.
    function _isSupportedAlgorithm(bytes32 algorithmId) internal pure virtual returns (bool) {
        return algorithmId == _AUDIT_SERVICE_ECDSA_ALGORITHM_ID;
    }

    function _requireValidEnvelope(AuditTypes.AuditEnvelope calldata envelope) internal pure virtual {
        if (envelope.eventHash == bytes32(0)) revert IAuditService.InvalidEventHash();
        if (envelope.schemaId == bytes32(0)) revert IAuditService.InvalidSchemaId();
        if (envelope.schemaVersion == bytes32(0)) revert IAuditService.InvalidSchemaVersion();
        if (envelope.schemaHash == bytes32(0)) revert IAuditService.InvalidSchemaHash();
        if (envelope.eip712TypeHash == bytes32(0)) revert IAuditService.InvalidEip712TypeHash();
        if (envelope.tenantId == bytes32(0)) revert IAuditService.InvalidTenantId();
        if (envelope.nonce == bytes32(0)) revert IAuditService.InvalidNonce();
    }

    function _isEnvelopeWellFormed(AuditTypes.AuditEnvelope calldata envelope) internal pure virtual returns (bool) {
        return (
            envelope.eventHash != bytes32(0) &&
            envelope.schemaId != bytes32(0) &&
            envelope.schemaVersion != bytes32(0) &&
            envelope.schemaHash != bytes32(0) &&
            envelope.eip712TypeHash != bytes32(0) &&
            envelope.tenantId != bytes32(0) &&
            envelope.nonce != bytes32(0)
        );
    }

    function _requireEnabledSchemaForEnvelope(
        AuditServiceStorage storage $,
        AuditTypes.AuditEnvelope calldata envelope
    ) internal view virtual {
        if (!_schemaExists($, envelope.schemaId, envelope.schemaVersion)) {
            revert IAuditService.SchemaNotRegistered(envelope.schemaId, envelope.schemaVersion);
        }

        AuditTypes.Schema storage schema = $.schemas[envelope.schemaId][envelope.schemaVersion];

        if (!schema.enabled) {
            revert IAuditService.SchemaDisabled(envelope.schemaId, envelope.schemaVersion);
        }

        if (schema.schemaHash != envelope.schemaHash) {
            revert IAuditService.SchemaHashMismatch(envelope.schemaId, envelope.schemaVersion);
        }

        if (schema.eip712TypeHash != envelope.eip712TypeHash) {
            revert IAuditService.Eip712TypeHashMismatch(envelope.schemaId, envelope.schemaVersion);
        }
    }

    function _schemaExists(
        AuditServiceStorage storage $,
        bytes32 schemaId,
        bytes32 schemaVersion
    ) internal view virtual returns (bool) {
        return $.schemas[schemaId][schemaVersion].schemaHash != bytes32(0);
    }

    function _isSchemaEnabledForEnvelope(
        AuditServiceStorage storage $,
        AuditTypes.AuditEnvelope calldata envelope
    ) internal view virtual returns (bool) {
        if (!_schemaExists($, envelope.schemaId, envelope.schemaVersion)) return false;

        AuditTypes.Schema storage schema = $.schemas[envelope.schemaId][envelope.schemaVersion];

        return (
            schema.enabled &&
            schema.schemaHash == envelope.schemaHash &&
            schema.eip712TypeHash == envelope.eip712TypeHash
        );
    }

    function _algorithmExists(
        AuditServiceStorage storage $,
        bytes32 algorithmId
    ) internal view virtual returns (bool) {
        return $.algorithms[algorithmId].algorithmId != bytes32(0);
    }

    function _keyExists(AuditServiceStorage storage $, bytes32 keyId) internal view virtual returns (bool) {
        return $.keys[keyId].keyId != bytes32(0);
    }

    function _exists(
        AuditServiceStorage storage $,
        bytes32 eventHash
    ) internal view virtual returns (bool) {
        return $.anchors[eventHash].eventHash != bytes32(0);
    }

    // Activeness is derived purely from timestamps so historical signatures
    // remain auditable: a revoked key must still report active for timestamps
    // before its revocation.
    function _isKeyActiveAt(
        AuditServiceStorage storage $,
        bytes32 keyId,
        uint64 timestamp
    ) internal view virtual returns (bool) {
        if (!_keyExists($, keyId)) return false;

        AuditTypes.Key storage key = $.keys[keyId];

        if (key.registeredAt == 0 || key.registeredAt > timestamp) return false;
        if (key.revokedAt != 0 && key.revokedAt <= timestamp) return false;
        if (key.expiresAt != 0 && key.expiresAt <= timestamp) return false;

        return true;
    }

    function _domainSeparatorV4() internal view virtual returns (bytes32) {
        return keccak256(
            abi.encode(
                _EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(_AUDIT_SERVICE_EIP712_NAME)),
                keccak256(bytes(_AUDIT_SERVICE_EIP712_VERSION)),
                block.chainid,
                address(this)
            )
        );
    }

    function _blockTimestamp64() internal view virtual returns (uint64) {
        return uint64(_blockTimestamp());
    }

    /*//////////////////////////////////////////////////////////////
                        ERC-165 INTROSPECTION
    //////////////////////////////////////////////////////////////*/

    function _implementedInterfaces()
        internal
        pure
        virtual
        override
        returns (bytes4[] memory interfaces_)
    {
        interfaces_ = new bytes4[](1);
        interfaces_[0] = type(IAuditService).interfaceId;
    }

    /*//////////////////////////////////////////////////////////////
                            STORAGE ACCESS
    //////////////////////////////////////////////////////////////*/

    function _auditServiceStorage()
        internal
        pure
        returns (AuditServiceStorage storage storage_)
    {
        bytes32 position = _AUDIT_SERVICE_STORAGE_POSITION;

        // slither-disable-start assembly
        // solhint-disable-next-line no-inline-assembly
        assembly {
            storage_.slot := position
        }
        // slither-disable-end assembly
    }
}
