// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Key } from "./AuditTypes.sol";

/// @title IKeyRegistry
/// @notice Registry of public keys and supported signature algorithms.
///
/// @dev ─── OZ Implementation Notes ────────────────────────────────────────────
///  The implementation contract should use:
///  - UUPSUpgradeable    : proxy upgrade pattern (OZ v5)
///  - AccessControlUpgradeable : role-based access control (OZ v5)
///  - ERC7201 namespaced storage: isolate storage from proxy slots
///
///  Suggested roles:
///  - DEFAULT_ADMIN_ROLE : manages other roles + UUPS upgrade authorization
///  - KEY_MANAGER_ROLE   : registerKey() — CTB Orchestrator wallet
///  - REVOKER_ROLE       : revokeKey() — can be a separate incident-response process
///  - ALGO_MANAGER_ROLE  : registerAlgorithm(), updateAlgorithmVerifier()
///
/// ─── Key lifecycle ────────────────────────────────────────────────────────────
///  REGISTERED → REVOKED (terminal; records are never deleted from storage)
///  REGISTERED → EXPIRED (time-based; expiresAt reached without explicit revocation)
///  Both revoked and expired keys remain permanently readable for historical verification.
///
/// ─── publicKey encoding by algorithmId ────────────────────────────────────────
///  ALG_ECDSA_SECP256K1  → 65 bytes uncompressed: 0x04 || x(32) || y(32)
///  ALG_ECDSA_SECP256R1  → 64 bytes: qx(32) || qy(32), big-endian
///  ALG_ED25519          → 32 bytes raw public key
///  ALG_RSA_PKCS1_SHA256 → DER-encoded SubjectPublicKeyInfo (variable, typically 270+ bytes)
///  ALG_ML_DSA_44        → raw bytes per NIST FIPS 204 §9.1 (1312 bytes)
///
/// ─── Algorithm verifiers ─────────────────────────────────────────────────────
///  ALG_ECDSA_SECP256K1  : custom EcdsaSecp256k1Verifier (OZ ECDSA.tryRecover)
///  ALG_ECDSA_SECP256R1  : OZ ERC7913P256Verifier (RIP-7212 + Solidity fallback)
///  ALG_RSA_PKCS1_SHA256 : OZ ERC7913RSAVerifier
///  ALG_ML_DSA_44        : custom MlDsa44Verifier (attestation only — no EVM precompile)
interface IKeyRegistry {

    // ── Errors ───────────────────────────────────────────────────────────────

    error KeyAlreadyExists(bytes32 keyId);
    error KeyNotFound(bytes32 keyId);
    error KeyAlreadyRevoked(bytes32 keyId);
    error AlgorithmNotSupported(bytes32 algorithmId);
    error AlgorithmAlreadyRegistered(bytes32 algorithmId);
    error AlgorithmNotFound(bytes32 algorithmId);
    error InvalidPublicKey(bytes32 keyId);
    error InvalidExpiresAt(bytes32 keyId, uint64 expiresAt);

    // ── Events ───────────────────────────────────────────────────────────────

    /// @dev publicKey is NOT indexed: indexing dynamic bytes stores only keccak256(value),
    ///      making the actual key bytes unrecoverable from the topic. It is emitted as
    ///      non-indexed data so auditors can recover the full public key from event logs.
    event KeyRegistered(
        bytes32 indexed keyId,
        bytes32 indexed tenantId,
        bytes32 indexed algorithmId,
        bytes           publicKey,
        uint64          registeredAt,
        uint64          expiresAt
    );

    event KeyRevoked(
        bytes32 indexed keyId,
        bytes32 indexed tenantId,
        uint64          revokedAt,
        address         revokedBy
    );

    event AlgorithmRegistered(
        bytes32 indexed algorithmId,
        address indexed verifier
    );

    event AlgorithmVerifierUpdated(
        bytes32 indexed algorithmId,
        address         oldVerifier,
        address         newVerifier
    );

    // ── Key management ────────────────────────────────────────────────────────

    /// @notice Registers a new public key for a tenant.
    /// @dev Caller must have KEY_MANAGER_ROLE.
    ///      algorithmId must have a registered ISignatureVerifier; reverts with
    ///      AlgorithmNotSupported otherwise.
    ///      publicKey encoding must match the algorithm — see encoding table above.
    /// @param keyId       Unique identifier, e.g. keccak256(tenantId || signerIndex).
    /// @param algorithmId Must match a registered ISignatureVerifier.
    /// @param publicKey   Raw public key bytes (format defined by algorithmId).
    /// @param tenantId    Owning tenant.
    /// @param expiresAt   Unix timestamp of key expiry. 0 = perpetual.
    function registerKey(
        bytes32        keyId,
        bytes32        algorithmId,
        bytes calldata publicKey,
        bytes32        tenantId,
        uint64         expiresAt
    ) external;

    /// @notice Permanently revokes a key.
    /// @dev Caller must have REVOKER_ROLE.
    ///      Receipts anchored before revocation remain verifiable via isActiveAt().
    ///      Revocation is terminal — a revoked key cannot be reinstated.
    function revokeKey(bytes32 keyId) external;

    // ── Algorithm management ──────────────────────────────────────────────────

    /// @notice Registers a new signature algorithm with its ISignatureVerifier.
    /// @dev Caller must have ALGO_MANAGER_ROLE.
    ///      Use algorithm constants from AuditTypes.sol.
    function registerAlgorithm(bytes32 algorithmId, address verifier) external;

    /// @notice Replaces the verifier for an existing algorithm.
    /// @dev Use to upgrade a verifier implementation without changing algorithmId.
    ///      Caller must have ALGO_MANAGER_ROLE.
    function updateAlgorithmVerifier(bytes32 algorithmId, address newVerifier) external;

    // ── Queries ───────────────────────────────────────────────────────────────

    /// @notice Returns the full Key record. Reverts with KeyNotFound if absent.
    function getKey(bytes32 keyId) external view returns (Key memory);

    /// @notice Returns true if the key exists, is not revoked, and is not expired.
    /// @dev Equivalent to isActiveAt(keyId, uint64(block.timestamp)).
    function isActive(bytes32 keyId) external view returns (bool);

    /// @notice Returns true if the key was active at the given past timestamp.
    /// @dev A key is active at timestamp T if and only if ALL three conditions hold:
    ///        1. key.registeredAt <= T                        (was already registered)
    ///        2. key.revokedAt == 0 || key.revokedAt > T      (not yet revoked)
    ///        3. key.expiresAt == 0 || key.expiresAt > T      (not yet expired)
    ///      This is the critical function for validating historical receipts after a key
    ///      has been revoked or expired. A receipt anchored before revocation/expiry
    ///      is still valid even if isActive() now returns false.
    ///      Example: key expires at T=100; receipt anchored at T=80 → isActiveAt(id, 80) = true.
    /// @param keyId      The key to check.
    /// @param timestamp  block.timestamp value at the time of the original anchor.
    function isActiveAt(bytes32 keyId, uint64 timestamp) external view returns (bool);

    /// @notice Returns the ISignatureVerifier address for an algorithmId.
    ///         Returns address(0) if the algorithm is not registered.
    function getVerifier(bytes32 algorithmId) external view returns (address);

    // ── Versioning ────────────────────────────────────────────────────────────

    /// @notice Returns the implementation version (e.g. "1", "2").
    /// @dev Each UUPS implementation overrides this with the next version string.
    ///      Upgrade history is also available via Upgraded(address) events (ERC-1967).
    function version() external pure returns (string memory);
}
