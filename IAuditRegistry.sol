// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { TenantContext, SignerInput, SignerRecord, AuditEntry, VerificationStatus, AuditStatus } from "./AuditTypes.sol";
import { IAuditEncoder } from "./IAuditEncoder.sol";
import { IKeyRegistry }  from "./IKeyRegistry.sol";

/// @title IAuditRegistry
/// @notice Immutable on-chain anchor for signed audit receipts.
///
/// @dev ─── OZ Implementation Notes ────────────────────────────────────────────
///  The implementation contract should use:
///  - UUPSUpgradeable         : proxy upgrade pattern (OZ v5)
///  - OwnableUpgradeable      : single-owner access control (CTB Orchestrator)
///  - ERC7201 namespaced storage: isolate storage across upgrades
///    Namespace: "audit.storage.AuditRegistry"
///    Storage struct holds:
///      mapping(bytes32 => AuditEntry)    entries
///      mapping(bytes32 => SignerRecord[]) signers      ← separate to avoid getter omission
///      address                            encoder
///      address                            keyRegistry
///
/// ─── What is audited ──────────────────────────────────────────────────────────
///  rawData: the original data record (access log, consent doc, DB row...).
///  rawData is stored off-chain in the tenant's system and NEVER touches this contract.
///
/// ─── Full signing and anchoring flow ─────────────────────────────────────────
///  Off-chain (CTB Audit Node):
///    1. canonicalData  = RFC8785_JCS(rawData)              // deterministic JSON
///    2. rawDataHash    = keccak256(canonicalData)           // NEVER stored on-chain
///    3. messageToSign  = AuditEncoder.computeMessageHash(
///                            rawDataHash, tenant.id, tenant.parentId,
///                            status, schemaVersion, address(this proxy)
///                        )
///    4. sig_X          = Sign(privateKey_X, messageToSign) // per signer, independent
///    5. Verify all sig_X cryptographically before calling anchor()
///    6. eventHash      = HMAC-SHA256(tenantKey, rawDataHash) // privacy layer
///    7. Call anchor(eventHash, tenant, status, schemaVersion, signers)
///
///  On-chain (this contract):
///    - Validates all keyIds are active in KeyRegistry at current block.timestamp
///    - Stores AuditEntry + SignerRecord[] (with signatureCommitment per signer)
///    - Emits EntryAnchored with full signature bytes in event data (permanent log)
///
/// ─── Trust model (CRITICAL — read before implementing) ───────────────────────
///  anchor() is restricted to onlyOwner (CTB Orchestrator wallet).
///  The contract validates key activity in KeyRegistry but does NOT verify signatures
///  cryptographically on-chain. The Orchestrator is trusted to have verified all
///  signatures off-chain (step 5 above) before calling anchor().
///  This is the explicit trust assumption of the SaaS model. If the Orchestrator
///  is compromised, false receipts could be anchored. Mitigation: the Orchestrator
///  wallet should be a hardware-secured key or multisig (future enhancement).
///  Trustlessness is provided post-hoc: signatures + public keys are both public,
///  so any third party can verify any receipt independently at any time.
///
/// ─── Trustless verification (auditor, off-chain, any language) ───────────────
///  Auditor has rawData + tenantKey (from company or legal process):
///    1. canonicalData  = RFC8785_JCS(rawData)
///    2. rawDataHash    = keccak256(canonicalData)
///    3. HMAC-SHA256(tenantKey, rawDataHash) == on-chain eventHash               ✓
///    4. messageToSign  = AuditEncoder.computeMessageHash(rawDataHash, ...)
///    5. For each SignerRecord on-chain:
///         signerInput = recover from EntryAnchored event (full signature bytes)
///         keccak256(signerInput.signature) == SignerRecord.signatureCommitment   ✓
///         pubKey = KeyRegistry.getKey(signerId).publicKey
///         KeyRegistry.isActiveAt(signerId, entry.anchoredAt) == true            ✓
///         ISignatureVerifier(verifier).verify(pubKey, messageToSign, sig)
///           == ERC7913_MAGIC_VALUE                                               ✓
///
/// ─── Privacy and right-to-erasure ────────────────────────────────────────────
///  eventHash = HMAC-SHA256(tenantKey, rawDataHash). Destroy tenantKey →
///  eventHash cannot be linked to any data. GDPR Art. 17 / LGPD Art. 18 compliant.
///  rawDataHash is never emitted or stored — a blockchain observer cannot match
///  on-chain records to original data without tenantKey.
///
/// ─── Historical encoder tracking ─────────────────────────────────────────────
///  When setEncoder() is called (AuditEncoder upgrade), the EncoderUpdated event
///  records oldEncoder + newEncoder. Off-chain verifiers must use the encoder that
///  was active when a receipt was anchored. Use EncoderUpdated event history to
///  determine which AuditEncoder address to call for any given anchoredAt timestamp.
///
/// ─── Gas estimates (Polygon PoS, 30 gwei, POL ≈ $0.10) ──────────────────────
///  Dominant cost is SSTORE for SignerRecord (signatureCommitment = 1 slot = 22,100 gas).
///  Full signatures are in event logs (8 gas/byte) — NOT in storage.
///
///  1 ECDSA signer:               ~120,000 gas  ≈ $0.00036
///  2 ECDSA signers (ExplainMed): ~190,000 gas  ≈ $0.00057
///  1 ML-DSA-44 signer:           ~145,000 gas  ≈ $0.00044
///    (storage same as ECDSA — 1 slot for commitment;
///     event log extra: 2,420 bytes × 8 = 19,360 gas)
///
///  Note: ML-DSA verification is off-chain only — no EVM precompile exists.
///  The MlDsa44Verifier returns ERC7913_MAGIC_VALUE as an attestation.
interface IAuditRegistry {

    // ── Errors ───────────────────────────────────────────────────────────────

    error EntryAlreadyAnchored(bytes32 eventHash);
    error EntryNotFound(bytes32 eventHash);
    error NoSignersProvided();
    error SignerKeyNotFound(bytes32 keyId);
    error SignerKeyNotActive(bytes32 keyId, uint64 atTimestamp);
    error InvalidEncoderAddress();
    error InvalidKeyRegistryAddress();

    // ── Events ───────────────────────────────────────────────────────────────

    /// @notice Emitted when an audit receipt is anchored on-chain.
    /// @dev Full signature bytes in `signers` are permanently stored in event logs
    ///      (logs cannot be pruned post-hoc). This provides a second layer of
    ///      immutability beyond contract storage (which could change via UUPS upgrade).
    ///      Auditors recover signatures from this event to verify signatureCommitments
    ///      and run off-chain cryptographic verification.
    ///      Log cost: 8 gas/byte (G_logdata, Yellow Paper Berlin Appendix G).
    event EntryAnchored(
        bytes32 indexed eventHash,
        bytes32 indexed tenantId,
        bytes32 indexed parentTenantId,
        SignerInput[]   signers,
        AuditStatus           status,
        bytes32         schemaVersion,
        uint64          anchoredAt
    );

    /// @notice Emitted when the AuditEncoder reference is updated.
    /// @dev Off-chain verifiers must use the encoder active at the time of anchoring.
    ///      Use this event history to determine which AuditEncoder address to call
    ///      for receipts anchored in a given time window.
    event EncoderUpdated(
        address indexed oldEncoder,
        address indexed newEncoder
    );

    /// @notice Emitted when the KeyRegistry reference is updated.
    event KeyRegistryUpdated(
        address indexed oldRegistry,
        address indexed newRegistry
    );

    // ── Write functions (onlyOwner — CTB Orchestrator) ───────────────────────

    /// @notice Anchors a single audit receipt on-chain.
    ///
    /// @dev Trust model: caller (CTB Orchestrator, onlyOwner) MUST verify all
    ///      signatures cryptographically off-chain before calling this function.
    ///      This contract validates key activity but does NOT verify signatures.
    ///      See interface-level trust model documentation above.
    ///
    ///      For each signer in `signers`:
    ///        1. Verifies KeyRegistry.isActiveAt(signer.keyId, block.timestamp) — reverts
    ///           with SignerKeyNotActive if false.
    ///        2. Stores SignerRecord { keyId, algorithmId, keccak256(signer.signature) }.
    ///        3. Full signature bytes are emitted in EntryAnchored — NOT stored in storage.
    ///
    ///      Caller responsibilities (verified off-chain before calling):
    ///        - All signatures are cryptographically valid.
    ///        - ECDSA signatures are canonicalized to low-s.
    ///        - eventHash = HMAC-SHA256(tenantKey, rawDataHash).
    ///        - rawDataHash = keccak256(RFC8785_JCS(rawData)).
    ///
    /// @param eventHash     HMAC-SHA256(tenantKey, rawDataHash) — on-chain commitment.
    /// @param tenant        Tenant hierarchy context (id + parentId).
    /// @param status        STATUS_ACCEPTED (0) or STATUS_DENIED (1).
    /// @param schemaVersion Receipt schema version identifier.
    /// @param signers       Signer data: keyId + algorithmId + full signature bytes.
    function anchor(
        bytes32               eventHash,
        TenantContext calldata tenant,
        AuditStatus           status,   // uint8 → AuditStatus
        bytes32               schemaVersion,
        SignerInput[] calldata signers
    ) external;

    /// @notice Updates the AuditEncoder reference to a new deployment.
    /// @dev Emits EncoderUpdated. Historical receipts remain verifiable against
    ///      their original encoder — use EncoderUpdated event history to find it.
    ///      Caller must be owner.
    function setEncoder(address newEncoder) external;

    /// @notice Updates the KeyRegistry reference.
    /// @dev Caller must be owner.
    function setKeyRegistry(address newKeyRegistry) external;

    // ── Read functions (public) ───────────────────────────────────────────────

    /// @notice Returns true if an entry exists for the given eventHash.
    function exists(bytes32 eventHash) external view returns (bool);

    /// @notice Returns AuditEntry metadata for a given eventHash.
    /// @dev Does not include SignerRecord[] — use getSigners() or getEntryWithSigners().
    function getEntry(bytes32 eventHash) external view returns (AuditEntry memory);

    /// @notice Returns the on-chain SignerRecord[] for a given eventHash.
    /// @dev Contains signatureCommitment (keccak256 of signature), not full bytes.
    ///      Full signatures are recoverable from the EntryAnchored event log.
    function getSigners(bytes32 eventHash) external view returns (SignerRecord[] memory);

    /// @notice Returns entry metadata and signer records in a single call.
    /// @dev Convenience getter for off-chain clients that need both.
    function getEntryWithSigners(bytes32 eventHash)
        external view
        returns (AuditEntry memory entry, SignerRecord[] memory signers);

    /// @notice Returns the current AuditEncoder contract address.
    function getEncoder() external view returns (IAuditEncoder);

    /// @notice Returns the current KeyRegistry contract address.
    function getKeyRegistry() external view returns (IKeyRegistry);

    // ── Versioning ────────────────────────────────────────────────────────────

    /// @notice Returns the implementation version (e.g. "1", "2").
    /// @dev Each UUPS implementation overrides this with the next version string.
    ///      Upgrade history is also available via Upgraded(address) events (ERC-1967).
    function version() external pure returns (string memory);

    // ── Batch anchoring ───────────────────────────────────────────────────────

    /// @notice Anchors multiple receipts in a single transaction.
    /// @dev Convenience for the CTB Orchestrator when multiple events are ready.
    ///      Calls _anchor() for each item individually — per-item validation and
    ///      event emission are preserved. Not a Merkle root batch.
    ///      All arrays must have equal length.
    function anchorBatch(
        bytes32[]         calldata eventHashes,
        TenantContext[]   calldata tenants,
        AuditStatus[]     calldata statuses,   // uint8[] → AuditStatus[]
        bytes32[]         calldata schemaVersions,
        SignerInput[][]   calldata signersBatch
    ) external;

    // ── On-chain verification oracle ──────────────────────────────────────────

    /// @notice Verifies an anchored receipt on-chain using injected raw data.
    /// @dev View function — call via eth_call, not in a transaction.
    ///      rawDataHash is injected by the auditor to reconstruct messageToSign on-chain.
    ///      It is not persisted — privacy is maintained.
    ///      fullSignatures must match the order of SignerRecord[] for that eventHash.
    ///      For algorithms without on-chain support (ML-DSA, Ed25519), the verifier
    ///      may revert, returning NOT_SUPPORTED_ONCHAIN instead of INVALID_SIGNATURE.
    /// @param eventHash      The on-chain commitment to verify.
    /// @param rawDataHash    keccak256(RFC8785_JCS(rawData)) — computed by the auditor.
    /// @param fullSignatures Full signature bytes per signer, in SignerRecord[] order.
    /// @return results       VerificationStatus per signer.
    function verifyRecord(
        bytes32   eventHash,
        bytes32   rawDataHash,
        bytes[] calldata fullSignatures
    ) external view returns (VerificationStatus[] memory results);
}
