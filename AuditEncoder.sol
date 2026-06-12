// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { TenantContext, AUDIT_MESSAGE_TYPEHASH, TENANT_CONTEXT_TYPEHASH, AuditStatus } from "./AuditTypes.sol";
import { IAuditEncoder } from "./IAuditEncoder.sol";

/**
 * @title AuditEncoder
 * @notice Implementación inmutable del estándar de codificación EIP-712 para el CTB Audit Service.
 * @dev Desplegado sin proxy (no UUPS). Garantiza que los recibos históricos sean siempre
 *      verificables independientemente de futuras actualizaciones de AuditRegistry.
 *
 *      ERC-5267 (eip712Domain): implementado en AuditRegistry, no aquí.
 *      AuditRegistry conoce su propia address (el verifyingContract correcto).
 *      AuditEncoder sirve a múltiples registries — no puede afirmar un solo verifyingContract.
 *
 *      INMUTABILIDAD: este contrato no contiene selfdestruct ni delegatecall.
 *      Verificar bytecode pre-deploy:
 *        solc --bin --opcodes AuditEncoder.sol | grep -E "SELFDESTRUCT|DELEGATECALL"
 */
contract AuditEncoder is IAuditEncoder {
    string public constant SIGNING_DOMAIN = "AuditRegistry";

    // Almacenado en storage (constructor-set). `view` en lugar de `pure`.
    // Inmutable en sentido de despliegue: se escribe una vez en el constructor
    // y nunca más. Una nueva versión del encoding implica desplegar un AuditEncoderV2
    // con _version = "2", no actualizar este contrato.
    string private _version;

    constructor(string memory version_) {
        _version = version_;
    }

    // ── Metadata ──────────────────────────────────────────────────────────────

    /// @inheritdoc IAuditEncoder
    function name() external pure override returns (string memory) {
        return SIGNING_DOMAIN;
    }

    /// @inheritdoc IAuditEncoder
    function version() external view override returns (string memory) {
        return _version;
    }

    // ── Core encoding ─────────────────────────────────────────────────────────

    /// @inheritdoc IAuditEncoder
    function computeMessageHash(
        bytes32 rawDataHash,
        bytes32 tenantId,
        bytes32 tenantParentId,
        AuditStatus   status,
        bytes32 schemaVersion,
        address verifyingContract
    ) external view override returns (bytes32) {
        // 1. hashStruct(TenantContext) — EIP-712: sub-structs nunca se inlinean
        bytes32 tenantHash = keccak256(abi.encode(
            TENANT_CONTEXT_TYPEHASH,
            tenantId,
            tenantParentId
        ));

        // 2. hashStruct(AuditMessage) — uint8 promovido a uint256 por abi.encode
        bytes32 structHash = keccak256(abi.encode(
            AUDIT_MESSAGE_TYPEHASH,
            rawDataHash,
            tenantHash,
            uint256(status),
            schemaVersion
        ));

        // 3. Hash final EIP-191 §1.1: "\x19\x01" || domainSeparator || structHash
        return MessageHashUtils.toTypedDataHash(
            domainSeparator(verifyingContract),
            structHash
        );
    }

    /// @inheritdoc IAuditEncoder
    function domainSeparator(address verifyingContract) public view override returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(SIGNING_DOMAIN)),
            keccak256(bytes(_version)),
            block.chainid,
            verifyingContract
        ));
    }
}