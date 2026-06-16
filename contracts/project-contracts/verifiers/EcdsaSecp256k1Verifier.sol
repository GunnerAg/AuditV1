// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ISignatureVerifier} from "../ISignatureVerifier.sol";

/// @title CTB ECDSA secp256k1 Signature Verifier
/// @notice Verifies EIP-712 digests using Ethereum-style ECDSA secp256k1 signatures.
/// @dev This verifier treats `publicKey` as abi.encode(address expectedSigner).
contract EcdsaSecp256k1Verifier is ISignatureVerifier {
    /// @notice Suggested algorithm id for registry usage.
    /// @dev The main Audit Service does not depend on this constant; it is provided for consistency.
    bytes32 public constant ALGORITHM_ID = keccak256("ECDSA_SECP256K1_EIP712");

    /// @inheritdoc ISignatureVerifier
    function verify(
        bytes32 digest,
        bytes calldata signature,
        bytes calldata publicKey
    ) external pure override returns (bool valid) {
        if (digest == bytes32(0)) return false;
        if (publicKey.length != 32) return false;

        address expectedSigner = abi.decode(publicKey, (address));
        if (expectedSigner == address(0)) return false;

        (address recovered, ECDSA.RecoverError error_, bytes32 errorArg) = ECDSA
            .tryRecover(digest, signature);
        errorArg;

        return
            error_ == ECDSA.RecoverError.NoError && recovered == expectedSigner;
    }
}
