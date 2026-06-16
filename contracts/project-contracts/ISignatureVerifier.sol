// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

/// @title CTB Signature Verifier Interface
/// @notice Generic signature verifier interface for algorithm-agnostic audit signatures.
/// @dev Implementations may verify ECDSA, P-256, RSA, lattice/PQ signatures, ZK proofs, etc.
interface ISignatureVerifier {
    /// @notice Verifies a signature over a canonical digest using raw encoded public key material.
    /// @param digest Canonical message digest. In V1 this is the EIP-712 digest of AuditEnvelope.
    /// @param signature Raw signature bytes. Format depends on the algorithm implementation.
    /// @param publicKey Raw public key bytes. Format depends on the algorithm implementation.
    /// @return valid True if the signature is valid for the digest and public key.
    function verify(
        bytes32 digest,
        bytes calldata signature,
        bytes calldata publicKey
    ) external view returns (bool valid);
}