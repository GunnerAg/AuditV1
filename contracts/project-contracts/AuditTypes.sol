// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

/// @title CTB Audit Service V1 Types
/// @notice Shared types for schemas, algorithms, keys and audit anchoring.
/// @dev Keep these structs append-only across upgrades when stored in ProjectStorage.
library AuditTypes {
    /// @notice Registered business schema/template.
    /// @dev The contract does not interpret the schema body. It only stores a commitment.
    struct Schema {
        bytes32 schemaId;
        bytes32 schemaVersion;
        bytes32 schemaHash;
        bytes32 eip712TypeHash;
        bool enabled;
    }

    /// @notice Registered cryptographic verification algorithm.
    /// @dev `verifier` is an external contract implementing ISignatureVerifier.
    struct Algorithm {
        bytes32 algorithmId;
        address verifier;
        bool enabled;
    }

    /// @notice Registered signer key.
    /// @dev `publicKey` is raw encoded key material. It is intentionally bytes, not address.
    /// @dev `active` is informational only and intentionally NOT consulted by
    ///      `_isKeyActiveAt`. Activeness is derived purely from
    ///      `registeredAt`/`revokedAt`/`expiresAt` so historical signatures
    ///      remain auditable across revocation.
    struct Key {
        bytes32 keyId;
        bytes32 algorithmId;
        bytes publicKey;
        bytes32 tenantId;
        uint64 registeredAt;
        uint64 expiresAt;
        uint64 revokedAt;
        bool active;
    }

    /// @notice EIP-712 typed envelope signed by audit nodes.
    /// @dev `eventHash` is the canonical hash/HMAC commitment of the real off-chain payload.
    /// @dev `status` is opaque to this contract. Its value range is defined
    ///      off-chain; the contract does not interpret or validate it.
    struct AuditEnvelope {
        bytes32 eventHash;
        bytes32 schemaId;
        bytes32 schemaVersion;
        bytes32 schemaHash;
        bytes32 eip712TypeHash;
        bytes32 tenantId;
        uint8 status;
        bytes32 nonce;
    }

    /// @notice Stored audit anchor.
    /// @dev `digest` is the final EIP-712 digest that was verified.
    /// @dev `status` is opaque to this contract. Its value range is defined
    ///      off-chain; the contract does not interpret or validate it.
    struct Anchor {
        bytes32 eventHash;
        bytes32 digest;
        bytes32 schemaId;
        bytes32 schemaVersion;
        bytes32 tenantId;
        uint8 status;
        uint64 anchoredAt;
        uint32 signerCount;
    }

    /// @notice Signature supplied when anchoring.
    /// @dev Signature format depends on the key's registered algorithm.
    struct SignatureInput {
        bytes32 keyId;
        bytes signature;
    }

    /// @notice Stored signer metadata for an anchored event.
    /// @dev Raw signatures are not stored, only commitments.
    struct SignerRecord {
        bytes32 signerId;
        bytes32 keyId;
        bytes32 algorithmId;
        bytes32 signatureCommitment;
        uint64 signedAt;
    }
}
