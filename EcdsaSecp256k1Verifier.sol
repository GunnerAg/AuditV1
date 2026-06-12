// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { ERC7913_MAGIC_VALUE, SIGNATURE_VERIFIER_INVALID } from "./AuditTypes.sol";
import { ISignatureVerifier } from "./ISignatureVerifier.sol";

/**
 * @title EcdsaSecp256k1Verifier
 * @notice Verificador ERC-7913 para firmas ECDSA sobre secp256k1 (Ethereum nativo).
 * @dev Usa ECDSA.tryRecover() de OpenZeppelin en lugar de recover() para evitar
 *      reverts en firmas malformadas. Cualquier error retorna INVALID (0xffffffff).
 *      La canonicalización low-s es responsabilidad del llamador (CTB Orchestrator).
 *      tryRecover() devuelve RecoverError.InvalidSignatureS si s > secp256k1n/2.
 */
contract EcdsaSecp256k1Verifier is ISignatureVerifier {

    /// @inheritdoc ISignatureVerifier
    function verify(
        bytes  calldata publicKey,
        bytes32         messageHash,
        bytes  calldata signature
    ) external pure override returns (bytes4) {

        if (publicKey.length != 65 || publicKey[0] != 0x04) return SIGNATURE_VERIFIER_INVALID;

        // Derivar la dirección Ethereum desde la clave pública (saltamos el byte 0x04)
        address expectedSigner = address(uint160(uint256(keccak256(publicKey[1:]))));

        // tryRecover nunca revierte — devuelve (address(0), error, bytes32(0)) en caso de fallo
        (address recovered, ECDSA.RecoverError err, ) = ECDSA.tryRecover(messageHash, signature);

        if (err != ECDSA.RecoverError.NoError) return 0xffffffff;
        if (recovered != expectedSigner)        return 0xffffffff;

        return ERC7913_MAGIC_VALUE;
    }

    /// @inheritdoc ISignatureVerifier
    function supportsOnChainVerification() external pure override returns (bool) {
        return true; // ecrecover es un precompile nativo de la EVM
    }
}
