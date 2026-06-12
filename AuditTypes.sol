// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// =============================================================================
// STRUCTS
// =============================================================================

/// @notice Position in the tenant hierarchy.
/// @dev parentId == bytes32(0) → root tenant (direct CTB customer).
///      For N-level hierarchies, follow parentId chain until bytes32(0).
struct TenantContext {
    bytes32 id;
    bytes32 parentId;
}

/// @notice Signer data provided as input to anchor().
/// @dev Full signature bytes are emitted in EntryAnchored event (permanent,
///      8 gas/byte in logs) and NOT stored in contract storage.
///      Only keccak256(signature) is persisted as signatureCommitment in SignerRecord.
struct SignerInput {
    bytes32 keyId;
    bytes signature;
}

/// @notice Signer record as persisted on-chain in contract storage.
/// @dev signatureCommitment = keccak256(signature).
///      Binding: proves a specific signature was anchored without storing full bytes.
///      The full signature is recoverable from the EntryAnchored event log.
///      algorithmId is denormalized here (also in KeyRegistry) to allow auditors
///      to read all relevant data from AuditRegistry without a cross-contract call.
struct SignerRecord {
    bytes32 keyId;
    bytes32 algorithmId;
    bytes32 signatureCommitment;
}

/// @notice Core audit entry metadata stored on-chain.
/// @dev SignerRecord[] is stored in a separate mapping(bytes32 => SignerRecord[])
///      keyed by eventHash to avoid Solidity's silent omission of dynamic arrays
///      in auto-generated public getters (documented in Solidity docs §Getter Functions).
struct AuditEntry {
    bytes32 eventHash;     
    TenantContext tenant;  
    bytes32 schemaVersion; 
    // --- Slot empaquetado (20 + 4 + 4 + 1 = 29 bytes) ---
    address encoder;       // El encoder usado en el momento del anclaje
    uint32 anchoredAt;     
    uint32 signerCount;    
    AuditStatus status;          
}

/// @notice Public key record stored in KeyRegistry.
/// @dev publicKey encoding by algorithmId:
///      ALG_ECDSA_SECP256K1 → 65 bytes uncompressed (0x04 || x || y)
///      ALG_ECDSA_SECP256R1 → 64 bytes (qx || qy), each 32 bytes big-endian
///      ALG_ED25519         → 32 bytes raw public key
///      ALG_RSA_PKCS1_SHA256 → DER-encoded SubjectPublicKeyInfo (variable length)
///      ALG_ML_DSA_44       → raw bytes per NIST FIPS 204 §9.1 (1312 bytes)
struct Key {
    bytes32 keyId;
    bytes32 algorithmId;
    bytes publicKey; // format defined by algorithmId — see encoding table above
    bytes32 tenantId;
    uint64 registeredAt;
    uint64 expiresAt; // 0 = perpetual; non-zero = unix timestamp of expiry
    uint64 revokedAt; // 0 = active; non-zero = unix timestamp of revocation
}

// =============================================================================
// STATUS CONSTANTS
// =============================================================================

enum AuditStatus { ACCEPTED, DENIED }

// EXPIRED is an off-chain state managed by CTB Orchestrator. Never persisted on-chain.

// =============================================================================
// ALGORITHM IDENTIFIERS
// keccak256("<IANA/COSE/FIPS-aligned identifier>")
// To add a new algorithm: deploy an ISignatureVerifier implementation and call
// IKeyRegistry.registerAlgorithm() — no contract upgrade required.
// =============================================================================

bytes32 constant ALG_ECDSA_SECP256K1 = keccak256("ECDSA_SECP256K1_KECCAK256");
bytes32 constant ALG_ECDSA_SECP256R1 = keccak256("ECDSA_SECP256R1_SHA256");
bytes32 constant ALG_ED25519 = keccak256("EDDSA_ED25519_SHA512");
bytes32 constant ALG_RSA_PKCS1_SHA256 = keccak256("RSASSA_PKCS1_v1_5_SHA256");
bytes32 constant ALG_ML_DSA_44 = keccak256("ML_DSA_44_SHA3_256");

// =============================================================================
// ERC-7913 MAGIC VALUE
// Returned by ISignatureVerifier.verify() on success.
// Equals bytes4(keccak256("verify(bytes,bytes32,bytes)"))
// OZ v5.4+ ships ERC7913P256Verifier and ERC7913RSAVerifier using this pattern.
// =============================================================================

bytes4 constant ERC7913_MAGIC_VALUE = 0x1626ba7e;
bytes4 constant SIGNATURE_VERIFIER_INVALID = 0xffffffff;

// =============================================================================
// EIP-712 TYPE HASHES
//
// AuditMessage is the struct signers sign. It is distinct from AuditEntry:
//   AuditMessage  contains rawDataHash (keccak256 of canonical data — what was certified).
//   AuditEntry    contains eventHash   (HMAC of rawDataHash — on-chain privacy commitment).
//
// encodeType rules (EIP-712 §Definition of encodeType):
//   1. Primary type first.
//   2. Referenced struct types appended in alphabetical order.
//   3. No spaces between concatenated type strings.
//
// encodeData rules:
//   1. Sub-structs replaced by hashStruct(sub) — never inlined.
//   2. uint8 padded to 32 bytes by abi.encode (EIP-712 §Encoding of Atomic Types).
// =============================================================================

/// @dev TenantContext has no sub-structs.
bytes32 constant TENANT_CONTEXT_TYPEHASH = keccak256(
    "TenantContext(bytes32 id,bytes32 parentId)"
);

/// @dev AuditMessage references TenantContext → appended alphabetically after primary type.
///      rawDataHash = keccak256(RFC8785_JCS(rawData)) — what signers certify.
bytes32 constant AUDIT_MESSAGE_TYPEHASH = keccak256(
    "AuditMessage(bytes32 rawDataHash,TenantContext tenant,AuditStatus status,bytes32 schemaVersion)"
    "TenantContext(bytes32 id,bytes32 parentId)"
);

// ── Enums locales ───────────────────────────────────────────────────────
enum VerificationStatus {
    VALID, // Verificación criptográfica exitosa on-chain
    INVALID_SIGNATURE, // Firma no coincide o no es válida
    NOT_SUPPORTED_ONCHAIN, // Algoritmo Post-Quantum (ej. ML-DSA) no verificable en EVM
    KEY_EXPIRED_AT_ANCHOR, // La clave no era válida en el momento del anclaje
    COMMITMENT_MISMATCH // La firma proporcionada no genera el hash guardado
}

// =============================================================================
// SHARED ERRORS
// Errors scoped to a single contract live in that contract's interface.
// =============================================================================

error InvalidKeyId();
error InvalidTenantId();
error InvalidEventHash();
error InvalidRawDataHash();
error SignerKeyNotActive(bytes32 keyId, uint64 atTimestamp);
error MismatchedSignaturesLength(uint256 expected, uint256 actual);
error MismatchedArrayLengths();
error SignerKeyNotFound(bytes32 keyId);