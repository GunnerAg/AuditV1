// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {ISignatureVerifier} from "../ISignatureVerifier.sol";

/// @title AlwaysValidSignatureVerifier
/// @notice Test verifier whose `verify` always returns true.
/// @dev Test-only. Never deploy to production.
contract AlwaysValidSignatureVerifier is ISignatureVerifier {
    function verify(
        bytes32,
        bytes calldata,
        bytes calldata
    ) external pure override returns (bool valid) {
        return true;
    }
}

/// @title AlwaysInvalidSignatureVerifier
/// @notice Test verifier whose `verify` always returns false.
/// @dev Test-only. Never deploy to production.
contract AlwaysInvalidSignatureVerifier is ISignatureVerifier {
    function verify(
        bytes32,
        bytes calldata,
        bytes calldata
    ) external pure override returns (bool valid) {
        return false;
    }
}

/// @title RevertingSignatureVerifier
/// @notice Test verifier whose `verify` always reverts.
/// @dev Test-only. Never deploy to production. Used to exercise the try/catch
///      fallback inside `_callVerifier`.
contract RevertingSignatureVerifier is ISignatureVerifier {
    error VerifierIntentionallyReverted();

    function verify(
        bytes32,
        bytes calldata,
        bytes calldata
    ) external pure override returns (bool) {
        revert VerifierIntentionallyReverted();
    }
}
