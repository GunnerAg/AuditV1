// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { P256 } from "@openzeppelin/contracts/utils/cryptography/P256.sol";
import { ERC7913_MAGIC_VALUE } from "./AuditTypes.sol";
import { ISignatureVerifier } from "./ISignatureVerifier.sol";

/**
 * @title EcdsaSecp256r1Verifier
 * @notice Verificador ERC-7913 para firmas ECDSA sobre secp256r1 / P-256 (FIPS 186-4).
 * @dev Usado por Passkeys (WebAuthn/FIDO2), Apple Secure Enclave y Android Keystore.
 *      Usa OZ P256.verify() que intenta el precompile RIP-7212 (address 0x100) en chains
 *      que lo soportan (Polygon zkEVM, zkSync, etc.) y hace fallback a Solidity puro.
 *      En Polygon PoS mainnet el precompile no está disponible — se usa el fallback.
 *      Requerimientos de longitud verificados explícitamente para evitar panics.
 */
contract EcdsaSecp256r1Verifier is ISignatureVerifier {

    /// @inheritdoc ISignatureVerifier
    /// @param publicKey 64 bytes: coordenada X (32 bytes) || coordenada Y (32 bytes), big-endian.
    /// @param signature 64 bytes: R (32 bytes) || S (32 bytes), big-endian.
    function verify(
        bytes  calldata publicKey,
        bytes32         messageHash,
        bytes  calldata signature
    ) external view override returns (bytes4) {
        if (publicKey.length != 64 || signature.length != 64) return 0xffffffff;

        bytes32 x = bytes32(publicKey[0:32]);
        bytes32 y = bytes32(publicKey[32:64]);
        bytes32 r = bytes32(signature[0:32]);
        bytes32 s = bytes32(signature[32:64]);

        if (P256.verify(messageHash, r, s, x, y)) return ERC7913_MAGIC_VALUE;

        return 0xffffffff;
    }

    /// @inheritdoc ISignatureVerifier
    function supportsOnChainVerification() external pure override returns (bool) {
        // Verificación on-chain vía precompile RIP-7212 (Polygon zkEVM) o Solidity fallback.
        // En Polygon PoS mainnet se usa el fallback Solidity — más costoso pero funcional.
        return true;
    }
}
