// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { TenantContext, AuditStatus } from "./AuditTypes.sol";

/// @title IAuditEncoder
/// @notice Immutable canonical EIP-712 encoding contract.
///
/// @dev ─── Why a separate immutable contract? ──────────────────────────────────
///  AuditRegistry is UUPS upgradeable. If computeMessageHash lived inside it,
///  an upgrade could silently change the encoding, making historical receipts
///  unverifiable against the new version. AuditEncoder is deployed ONCE, without
///  a proxy, and its address never changes. Any receipt anchored at any time can
///  always be re-verified using the same AuditEncoder at its original address.
///
/// ─── Versioning ───────────────────────────────────────────────────────────────
///  The version string is set at deploy time via constructor (e.g. "1", "2").
///  When a new encoding standard is needed, deploy a new AuditEncoder with the
///  next version. AuditRegistry.setEncoder() updates the reference for new anchors.
///  Historical receipts remain verifiable against the AuditEncoder used when they
///  were anchored — trackable via the EncoderUpdated event on AuditRegistry.
///
/// ─── OZ Implementation Notes ─────────────────────────────────────────────────
///  The implementation contract should:
///  - Use OZ MessageHashUtils.toTypedDataHash(domainSeparator, structHash) for
///    the final \x19\x01 prefix (do NOT hand-roll this).
///  - Build domainSeparator using EIP712_DOMAIN_TYPEHASH with block.chainid and
///    verifyingContract as parameter (NOT address(this) — encoder is not the registry).
///  - Mark all functions pure/view. No mutable storage. No proxy. No selfdestruct.
///  - ERC-5267 (eip712Domain) is implemented by AuditRegistry, NOT AuditEncoder.
///    AuditRegistry knows its own address (the correct verifyingContract).
///    AuditEncoder serves multiple registries — it cannot claim a single verifyingContract.
///
/// ─── Signing flow (off-chain, CTB Audit Node) ─────────────────────────────────
///  1. canonicalData  = RFC8785_JCS(rawData)              // deterministic JSON
///  2. rawDataHash    = keccak256(canonicalData)           // NEVER stored on-chain
///  3. messageToSign  = computeMessageHash(rawDataHash, tenant, status, schema, registryProxy)
///  4. sig_X          = Sign(privateKey_X, messageToSign) // any algorithm, parallel
///  5. eventHash      = HMAC-SHA256(tenantKey, rawDataHash) // privacy commitment
///
/// ─── Privacy model ────────────────────────────────────────────────────────────
///  rawDataHash is NEVER stored on-chain. A blockchain observer cannot match any
///  data to an eventHash without the tenantKey. Right-to-erasure: destroy tenantKey
///  → eventHash unverifiable. GDPR Art. 17 / LGPD Art. 18 compliant.
///
/// ─── Cross-chain replay protection ────────────────────────────────────────────
///  Domain separator includes block.chainid + verifyingContract.
///  A signature for Polygon PoS is invalid on ISBE and vice versa.
///  Dual-chain anchoring requires two independent signatures, two anchor() calls.
interface IAuditEncoder {

    // ── Metadata ──────────────────────────────────────────────────────────────

    /// @notice Returns the EIP-712 domain name ("AuditRegistry").
    function name() external pure returns (string memory);

    /// @notice Returns the encoding version set at deploy time (e.g. "1").
    /// @dev A new AuditEncoder with version "2" is deployed when the encoding spec changes.
    ///      AuditRegistry.setEncoder() activates it for new anchors.
    ///      Historical receipts remain verifiable against the original encoder.
    function version() external view returns (string memory);

    // ── Core encoding ─────────────────────────────────────────────────────────

    /// @notice Computes the EIP-712 AuditMessage hash that all signers must sign.
    ///
    /// @dev Encoding steps:
    ///  1. tenantHash  = keccak256(abi.encode(TENANT_CONTEXT_TYPEHASH, tenantId, tenantParentId))
    ///  2. structHash  = keccak256(abi.encode(
    ///                       AUDIT_MESSAGE_TYPEHASH,
    ///                       rawDataHash,
    ///                       tenantHash,        ← hashStruct(TenantContext), NOT inlined
    ///                       uint256(status),   ← padded to 32 bytes per EIP-712
    ///                       schemaVersion
    ///                   ))
    ///  3. return MessageHashUtils.toTypedDataHash(domainSeparator(verifyingContract), structHash)
    ///     i.e.   keccak256("\x19\x01" || domainSeparator || structHash)
    ///
    ///  IMPORTANT: verifyingContract MUST be the AuditRegistry PROXY address, not
    ///  the encoder's own address. This binds each signature to a specific registry
    ///  deployment, preventing cross-deployment replay attacks.
    ///
    /// @param rawDataHash        keccak256(RFC8785_JCS(rawData)) — computed off-chain.
    /// @param tenantId           Leaf tenant identifier.
    /// @param tenantParentId     Parent tenant (bytes32(0) if root tenant).
    /// @param status             STATUS_ACCEPTED (0) or STATUS_DENIED (1).
    /// @param schemaVersion      Receipt schema version identifier.
    /// @param verifyingContract  AuditRegistry proxy address.
    /// @return messageHash       The hash every signer must sign, regardless of algorithm.
    function computeMessageHash(
        bytes32 rawDataHash,
        bytes32 tenantId,
        bytes32 tenantParentId,
        AuditStatus   status,
        bytes32 schemaVersion,
        address verifyingContract
    ) external view returns (bytes32 messageHash);

    /// @notice Returns the EIP-712 domain separator for a given AuditRegistry deployment.
    /// @dev Rebuilt on every call — no cache needed since AuditEncoder has no mutable storage.
    ///      domain = keccak256(abi.encode(
    ///        EIP712_DOMAIN_TYPEHASH,
    ///        keccak256(bytes("AuditRegistry")),  ← protocol name
    ///        keccak256(bytes(version)),           ← set at deploy time
    ///        block.chainid,
    ///        verifyingContract                    ← AuditRegistry proxy
    ///      ))
    /// @param verifyingContract AuditRegistry proxy address.
    function domainSeparator(address verifyingContract) external view returns (bytes32);
}
