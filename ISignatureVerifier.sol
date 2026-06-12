// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC7913_MAGIC_VALUE } from "./AuditTypes.sol";

/// @title ISignatureVerifier
/// @notice Strategy interface for signature verification, aligned with ERC-7913.
///
/// @dev One stateless contract per algorithm implements this interface.
///      IKeyRegistry maps algorithmId → ISignatureVerifier address.
///
/// ─── OZ v5.4 ready-to-use implementations ────────────────────────────────────
///  - secp256k1 : CTB EcdsaSecp256k1Verifier (OZ ECDSA.tryRecover + ecrecover)
///  - secp256r1 : OZ ERC7913P256Verifier (RIP-7212 precompile + Solidity fallback)
///  - RSA       : OZ ERC7913RSAVerifier  (RSA PKCS#1 v1.5)
///  - ML-DSA-44 : custom MlDsa44Verifier — returns ERC7913_MAGIC_VALUE as attestation;
///                no EVM precompile; cryptographic verification always off-chain.
///
/// ─── Trust model ─────────────────────────────────────────────────────────────
///  anchor() does NOT call verify(). The CTB Orchestrator verifies all signatures
///  off-chain before calling anchor(). Verifiers are available for optional
///  third-party on-chain spot-checks via AuditRegistry.verifyRecord().
///  Trustlessness: signatureCommitment in storage + full signatures in event logs
///  + public keys in KeyRegistry — all public, all permanent.
///
/// ─── ECDSA malleability ──────────────────────────────────────────────────────
///  Implementations for secp256k1 and secp256r1 MUST reject high-s signatures
///  (s > N/2) to prevent malleability. OZ ECDSA.tryRecover() enforces this via
///  RecoverError.InvalidSignatureS. OZ P256.verify() enforces it by default.
///
/// ─── publicKey format by algorithmId ─────────────────────────────────────────
///  ALG_ECDSA_SECP256K1  → 65 bytes uncompressed (0x04 || x(32) || y(32))
///  ALG_ECDSA_SECP256R1  → 64 bytes (qx(32) || qy(32))
///  ALG_ED25519          → 32 bytes raw
///  ALG_RSA_PKCS1_SHA256 → DER-encoded SubjectPublicKeyInfo (variable)
///  ALG_ML_DSA_44        → 1312 bytes raw (NIST FIPS 204 §9.1)
interface ISignatureVerifier {

    /// @notice Verifies a signature over a message hash using the given public key.
    /// @dev Aligned with ERC-7913 IERC7913SignatureVerifier.
    ///      messageHash MUST be the EIP-712 AuditMessage hash from IAuditEncoder —
    ///      never a raw data hash or keccak256(rawData).
    /// @param key        Raw public key bytes. Format defined by algorithmId (see above).
    /// @param hash       EIP-712 AuditMessage hash from IAuditEncoder.computeMessageHash().
    /// @param signature  Raw signature bytes. ECDSA: low-s canonical form required.
    /// @return           ERC7913_MAGIC_VALUE (0x1626ba7e) if valid, 0xffffffff if not.
    function verify(
        bytes  calldata key,
        bytes32         hash,
        bytes  calldata signature
    ) external view returns (bytes4);

    /// @notice Returns true if this verifier performs real on-chain cryptographic verification.
    /// @dev false for post-quantum algorithms (ML-DSA, Ed25519) — no EVM precompile.
    ///      Those verifiers return ERC7913_MAGIC_VALUE as an attestation only.
    ///      Off-chain verification is always possible via signature logs + KeyRegistry.
    function supportsOnChainVerification() external pure returns (bool);
}
