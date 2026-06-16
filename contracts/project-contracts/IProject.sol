// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {AuditTypes} from "./AuditTypes.sol";

/// @title CTB Audit Service V1 Interface
/// @notice Public API for schema registration, algorithm registration, key management and audit anchoring.
interface IProject {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new schema/template is registered.
    /// @param schemaId Logical identifier of the schema.
    /// @param schemaVersion Version of the schema being registered.
    /// @param schemaHash Commitment to the off-chain schema body.
    /// @param eip712TypeHash Type hash used when EIP-712 signing this schema.
    event SchemaRegistered(
        bytes32 indexed schemaId,
        bytes32 indexed schemaVersion,
        bytes32 schemaHash,
        bytes32 eip712TypeHash
    );

    /// @notice Emitted when the enabled flag of a registered schema changes.
    /// @param schemaId Logical identifier of the schema.
    /// @param schemaVersion Version of the schema being toggled.
    /// @param enabled New enabled state.
    event SchemaEnabledSet(
        bytes32 indexed schemaId,
        bytes32 indexed schemaVersion,
        bool enabled
    );

    /// @notice Emitted when a new verification algorithm is registered.
    /// @param algorithmId Logical identifier of the algorithm.
    /// @param verifier Address of the external ISignatureVerifier implementation.
    event AlgorithmRegistered(
        bytes32 indexed algorithmId,
        address indexed verifier
    );

    /// @notice Emitted when the enabled flag of a registered algorithm changes.
    /// @param algorithmId Logical identifier of the algorithm.
    /// @param enabled New enabled state.
    event AlgorithmEnabledSet(bytes32 indexed algorithmId, bool enabled);

    /// @notice Emitted when a signer key is registered.
    /// @param keyId Logical identifier of the key.
    /// @param algorithmId Algorithm this key is bound to.
    /// @param tenantId Tenant the key belongs to.
    /// @param registeredAt Block timestamp at which the key was registered.
    /// @param expiresAt Absolute expiry timestamp (0 means no expiry).
    event KeyRegistered(
        bytes32 indexed keyId,
        bytes32 indexed algorithmId,
        bytes32 indexed tenantId,
        uint64 registeredAt,
        uint64 expiresAt
    );

    /// @notice Emitted when a previously active key is revoked.
    /// @param keyId Logical identifier of the revoked key.
    /// @param revokedAt Block timestamp at which the key was revoked.
    event KeyRevoked(bytes32 indexed keyId, uint64 revokedAt);

    /// @notice Emitted when an audit envelope is anchored on-chain.
    /// @dev The contract does not interpret or validate the `status` value range
    ///      — it is opaque and defined off-chain.
    /// @param eventHash Canonical hash/HMAC commitment of the off-chain payload.
    /// @param tenantId Tenant the audit event belongs to.
    /// @param schemaId Schema the envelope conforms to.
    /// @param schemaVersion Schema version the envelope conforms to.
    /// @param digest EIP-712 digest that was verified for this anchor.
    /// @param status Opaque application-level status code.
    /// @param signerCount Number of signers recorded for this anchor.
    /// @param anchoredAt Block timestamp at which the anchor was created.
    event AuditAnchored(
        bytes32 indexed eventHash,
        bytes32 indexed tenantId,
        bytes32 indexed schemaId,
        bytes32 schemaVersion,
        bytes32 digest,
        uint8 status,
        uint32 signerCount,
        uint64 anchoredAt
    );

    /// @notice Emitted once per signer when an audit envelope is anchored.
    /// @param eventHash Event hash of the anchored envelope.
    /// @param signerId Hash of (eventHash, keyId) uniquely identifying the signer entry.
    /// @param keyId Key that produced the signature.
    /// @param algorithmId Algorithm associated with the signing key.
    /// @param signatureCommitment keccak256 commitment of the raw signature bytes.
    /// @param signedAt Block timestamp at which the anchor was created.
    event AuditSignerRecorded(
        bytes32 indexed eventHash,
        bytes32 indexed signerId,
        bytes32 indexed keyId,
        bytes32 algorithmId,
        bytes32 signatureCommitment,
        uint64 signedAt
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a schemaId argument is zero.
    error InvalidSchemaId();
    /// @notice Thrown when a schemaVersion argument is zero.
    error InvalidSchemaVersion();
    /// @notice Thrown when a schemaHash argument is zero.
    error InvalidSchemaHash();
    /// @notice Thrown when the requested (schemaId, schemaVersion) pair is not registered.
    error SchemaNotRegistered(bytes32 schemaId, bytes32 schemaVersion);
    /// @notice Thrown when registering a (schemaId, schemaVersion) pair that already exists.
    error SchemaAlreadyRegistered(bytes32 schemaId, bytes32 schemaVersion);
    /// @notice Thrown when anchoring against a schema whose enabled flag is false.
    error SchemaDisabled(bytes32 schemaId, bytes32 schemaVersion);

    /// @notice Thrown when an algorithmId argument is zero.
    error InvalidAlgorithmId();
    /// @notice Thrown when a verifier address argument is the zero address.
    error InvalidVerifierAddress();
    /// @notice Thrown when an algorithm is not registered.
    error AlgorithmNotRegistered(bytes32 algorithmId);
    /// @notice Thrown when registering an algorithm that already exists.
    error AlgorithmAlreadyRegistered(bytes32 algorithmId);
    /// @notice Thrown when using an algorithm whose enabled flag is false.
    error AlgorithmDisabled(bytes32 algorithmId);

    /// @notice Thrown when a keyId argument is zero.
    error InvalidKeyId();
    /// @notice Thrown when the publicKey argument is empty.
    error InvalidPublicKey();
    /// @notice Thrown when a tenantId argument is zero.
    error InvalidTenantId();
    /// @notice Thrown when the requested key is not registered.
    error KeyNotRegistered(bytes32 keyId);
    /// @notice Thrown when registering a key that already exists.
    error KeyAlreadyRegistered(bytes32 keyId);
    /// @notice Thrown when a key is not active at the relevant timestamp.
    error KeyNotActive(bytes32 keyId);
    /// @notice Thrown when a signing key's tenant does not match the envelope's tenant.
    /// @param keyId Key whose tenant was mismatched.
    /// @param expectedTenantId Tenant expected by the envelope.
    /// @param actualTenantId Tenant the key is actually bound to.
    error KeyTenantMismatch(
        bytes32 keyId,
        bytes32 expectedTenantId,
        bytes32 actualTenantId
    );

    /// @notice Thrown when an envelope's eventHash is zero.
    error InvalidEventHash();
    /// @notice Thrown when an envelope's nonce is zero.
    error InvalidNonce();
    /// @notice Thrown when anchor is called with an empty signatures array.
    error NoSignaturesProvided();
    /// @notice Thrown when anchoring an eventHash that is already anchored.
    error EventAlreadyAnchored(bytes32 eventHash);
    /// @notice Thrown when reading an anchor that does not exist.
    error EventNotAnchored(bytes32 eventHash);
    /// @notice Thrown when a signature fails verification against the registered key.
    error InvalidSignature(bytes32 keyId);
    /// @notice Thrown when the same keyId is presented twice for the same eventHash.
    error DuplicateSigner(bytes32 eventHash, bytes32 keyId);
    /// @notice Thrown when reading a signer record that does not exist.
    error SignerNotFound(bytes32 eventHash, bytes32 keyId);
    /// @notice Thrown when registering a key whose expiry is not strictly in the future.
    error InvalidExpiresAt(bytes32 keyId, uint64 expiresAt);
    /// @notice Thrown when an envelope's eip712TypeHash is zero.
    error InvalidEip712TypeHash();
    /// @notice Thrown when an envelope's schemaHash does not match the registered schema.
    error SchemaHashMismatch(bytes32 schemaId, bytes32 schemaVersion);
    /// @notice Thrown when an envelope's eip712TypeHash does not match the registered schema.
    error Eip712TypeHashMismatch(bytes32 schemaId, bytes32 schemaVersion);

    /*//////////////////////////////////////////////////////////////
                            SCHEMA REGISTRY
    //////////////////////////////////////////////////////////////*/

    /// @notice Registers a new schema/template version. Newly registered schemas are enabled.
    /// @param schemaId Logical identifier of the schema.
    /// @param schemaVersion Version of the schema being registered.
    /// @param schemaHash Commitment to the off-chain schema body.
    /// @param eip712TypeHash Type hash used when EIP-712 signing this schema.
    function registerSchema(
        bytes32 schemaId,
        bytes32 schemaVersion,
        bytes32 schemaHash,
        bytes32 eip712TypeHash
    ) external;

    /// @notice Enables or disables a previously registered schema version.
    /// @param schemaId Logical identifier of the schema.
    /// @param schemaVersion Version of the schema to toggle.
    /// @param enabled New enabled state.
    function setSchemaEnabled(
        bytes32 schemaId,
        bytes32 schemaVersion,
        bool enabled
    ) external;

    /// @notice Reads a registered schema record.
    /// @param schemaId Logical identifier of the schema.
    /// @param schemaVersion Version of the schema to read.
    /// @return schema Stored schema record.
    function getSchema(
        bytes32 schemaId,
        bytes32 schemaVersion
    ) external view returns (AuditTypes.Schema memory schema);

    /*//////////////////////////////////////////////////////////////
                          ALGORITHM REGISTRY
    //////////////////////////////////////////////////////////////*/

    /// @notice Registers a verification algorithm. Newly registered algorithms are enabled.
    /// @param algorithmId Logical identifier of the algorithm.
    /// @param verifier Address of the external ISignatureVerifier implementation.
    function registerAlgorithm(bytes32 algorithmId, address verifier) external;

    /// @notice Enables or disables a previously registered algorithm.
    /// @param algorithmId Logical identifier of the algorithm to toggle.
    /// @param enabled New enabled state.
    function setAlgorithmEnabled(bytes32 algorithmId, bool enabled) external;

    /// @notice Reads a registered algorithm record.
    /// @param algorithmId Logical identifier of the algorithm to read.
    /// @return algorithm Stored algorithm record.
    function getAlgorithm(
        bytes32 algorithmId
    ) external view returns (AuditTypes.Algorithm memory algorithm);

    /*//////////////////////////////////////////////////////////////
                              KEY REGISTRY
    //////////////////////////////////////////////////////////////*/

    /// @notice Registers a signer key for the given tenant and algorithm.
    /// @param keyId Logical identifier of the key.
    /// @param algorithmId Algorithm this key is bound to. Must already be registered and enabled.
    /// @param publicKey Raw encoded public key material.
    /// @param tenantId Tenant the key belongs to.
    /// @param expiresAt Absolute expiry timestamp. Pass 0 for no expiry; if non-zero must be strictly greater than the current block timestamp.
    function registerKey(
        bytes32 keyId,
        bytes32 algorithmId,
        bytes calldata publicKey,
        bytes32 tenantId,
        uint64 expiresAt
    ) external;

    /// @notice Revokes a key currently active at block timestamp.
    /// @param keyId Logical identifier of the key to revoke.
    function revokeKey(bytes32 keyId) external;

    /// @notice Reads a registered key record.
    /// @param keyId Logical identifier of the key to read.
    /// @return key Stored key record.
    function getKey(
        bytes32 keyId
    ) external view returns (AuditTypes.Key memory key);

    /// @notice Returns whether a key is currently active at block timestamp.
    /// @param keyId Logical identifier of the key.
    /// @return active True if the key exists and is active at the current block timestamp.
    function isKeyActive(bytes32 keyId) external view returns (bool active);

    /// @notice Returns whether a key was active at the given timestamp.
    /// @dev Activeness is derived from registeredAt/revokedAt/expiresAt only.
    /// @param keyId Logical identifier of the key.
    /// @param timestamp Timestamp to evaluate activeness at.
    /// @return active True if the key existed and was active at `timestamp`.
    function isKeyActiveAt(
        bytes32 keyId,
        uint64 timestamp
    ) external view returns (bool active);

    /*//////////////////////////////////////////////////////////////
                        AUDIT ANCHORING
//////////////////////////////////////////////////////////////*/

    /// @notice Anchors an audit envelope with one or more verified signatures.
    /// @dev The `envelope.status` value is opaque to this contract; it is stored
    ///      and emitted verbatim and is not interpreted or validated.
    /// @param envelope EIP-712 envelope to anchor.
    /// @param signatures Array of signatures to verify against the envelope's digest.
    function anchor(
        AuditTypes.AuditEnvelope calldata envelope,
        AuditTypes.SignatureInput[] calldata signatures
    ) external;

    /// @notice Returns whether an event hash has been anchored.
    /// @param eventHash Event hash to check.
    /// @return exists_ True if the event hash is anchored.
    function exists(bytes32 eventHash) external view returns (bool exists_);

    /// @notice Reads the stored anchor for an event hash.
    /// @dev The returned `anchor_.status` is opaque and was not interpreted or
    ///      validated by this contract on the way in.
    /// @param eventHash Event hash to read.
    /// @return anchor_ Stored anchor record.
    function getAnchor(
        bytes32 eventHash
    ) external view returns (AuditTypes.Anchor memory anchor_);

    /// @notice Returns every signer record recorded for the given event hash.
    /// @param eventHash Event hash to read.
    /// @return signers Stored signer records in registration order.
    function getSigners(
        bytes32 eventHash
    ) external view returns (AuditTypes.SignerRecord[] memory signers);

    /// @notice Returns the signer record for the given (eventHash, keyId) pair.
    /// @param eventHash Event hash to read.
    /// @param keyId Key whose record to read.
    /// @return signer Stored signer record.
    function getSigner(
        bytes32 eventHash,
        bytes32 keyId
    ) external view returns (AuditTypes.SignerRecord memory signer);

    /// @notice Returns whether a (eventHash, keyId) pair has a recorded signer.
    /// @param eventHash Event hash to check.
    /// @param keyId Key to check.
    /// @return signed_ True if a signer record exists for the pair.
    function hasSigner(
        bytes32 eventHash,
        bytes32 keyId
    ) external view returns (bool signed_);

    /// @notice Returns the number of signers recorded for the given event hash.
    /// @param eventHash Event hash to check.
    /// @return count Number of stored signer records.
    function getSignerCount(
        bytes32 eventHash
    ) external view returns (uint256 count);

    /// @notice Verifies a single signature against an envelope without anchoring.
    /// @dev Returns false (no revert) when the envelope is not well-formed.
    /// @param envelope Envelope to verify against.
    /// @param signature Signature to verify.
    /// @return valid True if the signature is valid for the envelope's digest.
    function verifySignature(
        AuditTypes.AuditEnvelope calldata envelope,
        AuditTypes.SignatureInput calldata signature
    ) external view returns (bool valid);

    /// @notice Verifies multiple signatures against an envelope without anchoring.
    /// @dev Returns an all-false array when the envelope is not well-formed.
    /// @param envelope Envelope to verify against.
    /// @param signatures Signatures to verify.
    /// @return results Per-signature verification results, in input order.
    function verifySignatures(
        AuditTypes.AuditEnvelope calldata envelope,
        AuditTypes.SignatureInput[] calldata signatures
    ) external view returns (bool[] memory results);

    /// @notice Computes the EIP-712 digest of an envelope as used by anchor.
    /// @param envelope Envelope to hash.
    /// @return digest EIP-712 typed-data hash bound to this contract and chain.
    function hashEnvelope(
        AuditTypes.AuditEnvelope calldata envelope
    ) external view returns (bytes32 digest);

    /*//////////////////////////////////////////////////////////////
                                METADATA
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the EIP-712 domain parameters for this contract.
    /// @return fields Domain field mask (ERC-5267).
    /// @return name EIP-712 domain name.
    /// @return version EIP-712 domain version.
    /// @return chainId Chain ID bound into the domain separator.
    /// @return verifyingContract Address bound into the domain separator.
    /// @return salt Domain separator salt (unused, zero).
    /// @return extensions Domain extensions (unused, empty).
    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        );

    /// @notice Returns the EIP-712 domain version string.
    /// @return version_ EIP-712 domain version.
    function version() external pure returns (string memory version_);
}
