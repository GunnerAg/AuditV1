// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { IERC5267 } from "@openzeppelin/contracts/interfaces/IERC5267.sol";

import { TenantContext, SignerInput, SignerRecord, AuditEntry, ERC7913_MAGIC_VALUE, VerificationStatus, Key, MismatchedSignaturesLength, MismatchedArrayLengths, AuditStatus } from "./AuditTypes.sol";
import { IAuditEncoder } from "./IAuditEncoder.sol";
import { IKeyRegistry }  from "./IKeyRegistry.sol";
import { IAuditRegistry } from "./IAuditRegistry.sol";
import { ISignatureVerifier } from "./ISignatureVerifier.sol";

/**
 * @title AuditRegistry
 * @notice Orquestador principal y anclaje inmutable de recibos de auditoría.
 * @dev UUPS upgradeable. ERC-7201 namespaced storage. OZ v5.x.
 *      Implementa IERC5267 (eip712Domain): esta es la fuente correcta del domain separator
 *      porque AuditRegistry es el verifyingContract. AuditEncoder no implementa ERC-5267
 *      ya que sirve a múltiples registries y no puede afirmar un único verifyingContract.
 *
 *      Storage slot: keccak256(abi.encode(uint256(keccak256("ctb.storage.AuditRegistry")) - 1)) & ~bytes32(uint256(0xff))
 *      Verificar con Foundry antes de deploy:
 *        bytes32(uint256(keccak256(abi.encode(uint256(keccak256("ctb.storage.AuditRegistry")) - 1))) & ~uint256(0xff))
 */
contract AuditRegistry is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable,
    IERC5267,
    IAuditRegistry
{
    // ── Roles ─────────────────────────────────────────────────────────────────
    bytes32 public constant ANCHOR_ROLE = keccak256("ANCHOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ── ERC-7201 Namespaced Storage ───────────────────────────────────────────
    // keccak256(abi.encode(uint256(keccak256("ctb.storage.AuditRegistry")) - 1)) & ~bytes32(uint256(0xff))
    // Valor verificado en test: erc7201Slot("ctb.storage.AuditRegistry") == 0x310d5888...
    bytes32 private constant AuditRegistryStorageLocation =
        0x310d58885e22457c8b14b984d05d8a67803f44308bdc47afe96a3739dfbd8000;

    struct AuditRegistryStorage {
        mapping(bytes32 => AuditEntry)    entries;
        mapping(bytes32 => SignerRecord[]) signers;
        IAuditEncoder encoder;
        IKeyRegistry  keyRegistry;
    }

    function _getAuditRegistryStorage() private pure returns (AuditRegistryStorage storage $) {
        assembly { $.slot := AuditRegistryStorageLocation }
    }

    // ── Inicialización ────────────────────────────────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(
        address defaultAdmin,
        address initialEncoder,
        address initialKeyRegistry
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);

        AuditRegistryStorage storage $ = _getAuditRegistryStorage();
        if (initialEncoder    == address(0)) revert InvalidEncoderAddress();
        if (initialKeyRegistry == address(0)) revert InvalidKeyRegistryAddress();

        $.encoder     = IAuditEncoder(initialEncoder);
        $.keyRegistry = IKeyRegistry(initialKeyRegistry);
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // ── Versioning ────────────────────────────────────────────────────────────

    /// @notice Versión de esta implementación. Sobreescribir en V2 con "2", etc.
    function version() external pure virtual returns (string memory) { return "1"; }

    // ── ERC-5267: dominio EIP-712 de este contrato ────────────────────────────

    /**
     * @notice Retorna los componentes del dominio EIP-712 de este AuditRegistry.
     * @dev AuditRegistry es el verifyingContract correcto. El encoder delega aquí
     *      el eip712Domain() estándar. Herramientas como MetaMask y Etherscan usan
     *      esta función para mostrar y verificar el dominio de firma.
     *      El domain name y version se leen del AuditEncoder para coherencia.
     */
    function eip712Domain() external view override returns (
        bytes1          fields,
        string memory   name,
        string memory   ver,
        uint256         chainId,
        address         verifyingContract,
        bytes32         salt,
        uint256[] memory extensions
    ) {
        AuditRegistryStorage storage $ = _getAuditRegistryStorage();
        return (
            hex"0f",                       // name + version + chainId + verifyingContract
            $.encoder.name(),
            $.encoder.version(),
            block.chainid,
            address(this),                 // este proxy = el verifyingContract real
            bytes32(0),
            new uint256[](0)
        );
    }

    // ── Gestión de seguridad (PAUSER_ROLE) ────────────────────────────────────

    function pause()   external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    function setEncoder(address newEncoder) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newEncoder == address(0)) revert InvalidEncoderAddress();
        AuditRegistryStorage storage $ = _getAuditRegistryStorage();
        address old = address($.encoder);
        $.encoder = IAuditEncoder(newEncoder);
        emit EncoderUpdated(old, newEncoder);
    }

    function setKeyRegistry(address newKeyRegistry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newKeyRegistry == address(0)) revert InvalidKeyRegistryAddress();
        AuditRegistryStorage storage $ = _getAuditRegistryStorage();
        address old = address($.keyRegistry);
        $.keyRegistry = IKeyRegistry(newKeyRegistry);
        emit KeyRegistryUpdated(old, newKeyRegistry);
    }

    // ── Core: anclaje ─────────────────────────────────────────────────────────

    function anchor(
        bytes32               eventHash,
        TenantContext calldata tenant,
        AuditStatus           status,
        bytes32               schemaVersion,
        SignerInput[] calldata signers
    ) external onlyRole(ANCHOR_ROLE) whenNotPaused {
        _anchor(eventHash, tenant, status, schemaVersion, signers);
    }

    function anchorBatch(
        bytes32[]         calldata eventHashes,
        TenantContext[]   calldata tenants,
        AuditStatus[]     calldata statuses,   // uint8[] → AuditStatus[]
        bytes32[]         calldata schemaVersions,
        SignerInput[][]   calldata signersBatch
    ) external onlyRole(ANCHOR_ROLE) whenNotPaused {
        uint256 len = eventHashes.length;
        if (tenants.length != len || statuses.length != len ||
            schemaVersions.length != len || signersBatch.length != len)
            revert MismatchedArrayLengths();
        for (uint256 i = 0; i < len; i++) {
            _anchor(eventHashes[i], tenants[i], statuses[i], schemaVersions[i], signersBatch[i]);
        }
    }

    function _anchor(
        bytes32 eventHash,
        TenantContext calldata tenant,
        AuditStatus status,
        bytes32 schemaVersion,
        SignerInput[] calldata signers
    ) private {
        AuditRegistryStorage storage $ = _getAuditRegistryStorage();

        if ($.entries[eventHash].anchoredAt != 0) revert EntryAlreadyAnchored(eventHash);
        if (signers.length == 0) revert NoSignersProvided();

        uint64 ts = uint64(block.timestamp);

        // 1. Guardamos la entrada con el ENCODER ACTUAL fijo para siempre
        $.entries[eventHash] = AuditEntry({
            eventHash: eventHash,
            tenant: tenant,
            status: status,
            signerCount: uint32(signers.length),
            schemaVersion: schemaVersion,
            anchoredAt: uint32(ts),
            encoder: address($.encoder) 
        });

        for (uint256 i = 0; i < signers.length; i++) {
            // CORRECCIÓN: Key memory, no IKeyRegistry.Key memory
            Key memory keyData = $.keyRegistry.getKey(signers[i].keyId);
            
            if (!$.keyRegistry.isActive(signers[i].keyId)) {
                revert SignerKeyNotActive(signers[i].keyId, uint64(block.timestamp));
            }

            $.signers[eventHash].push(SignerRecord({
                keyId: signers[i].keyId,
                algorithmId: keyData.algorithmId, // Obtenido de la fuente de verdad
                signatureCommitment: keccak256(signers[i].signature)
            }));
        }

        emit EntryAnchored(eventHash, tenant.id, tenant.parentId, signers, status, schemaVersion, ts);
    }

    // ── Oráculo de verificación on-chain (view) ───────────────────────────────

    /**
     * @notice Verifica matemáticamente un recibo anclado.
     * @dev Función view — llamar vía eth_call, no en una transacción.
     *      rawDataHash se inyecta por el auditor para reconstruir messageToSign on-chain.
     *      No se almacena ni persiste — la privacidad se mantiene.
     *      Para algoritmos sin soporte on-chain (ML-DSA, Ed25519) el verifier
     *      puede revertir; se captura con try/catch → NOT_SUPPORTED_ONCHAIN.
     */
    function verifyRecord(
        bytes32   eventHash,
        bytes32   rawDataHash,
        bytes[] calldata fullSignatures
    ) external view returns (VerificationStatus[] memory results) {
       AuditRegistryStorage storage $ = _getAuditRegistryStorage();
        AuditEntry memory entry = $.entries[eventHash];
        if (entry.anchoredAt == 0) revert EntryNotFound(eventHash);

        // 3. EVITAR PANIC 50: Validación de grado industrial
        if (fullSignatures.length != entry.signerCount) {
            revert MismatchedSignaturesLength(entry.signerCount, fullSignatures.length);
        }

        SignerRecord[] memory records = $.signers[eventHash];
        results = new VerificationStatus[](records.length);

        // 4. USAR EL ENCODER HISTÓRICO: Garantiza verificación perpetua
        IAuditEncoder historicalEncoder = IAuditEncoder(entry.encoder);

        // Reconstruir messageToSign — AuditEncoder define el encoding canónico
       bytes32 messageToSign = historicalEncoder.computeMessageHash(
            rawDataHash,
            entry.tenant.id,
            entry.tenant.parentId,
            entry.status,
            entry.schemaVersion,
            address(this)
        );

        for (uint256 i = 0; i < records.length; i++) {
            // 1. Commitment: ¿es la misma firma que el orchestrator ancló?
            if (keccak256(fullSignatures[i]) != records[i].signatureCommitment) {
                results[i] = VerificationStatus.COMMITMENT_MISMATCH;
                continue;
            }

            // 2. ¿La clave era válida en el momento del anclaje?
            if (!$.keyRegistry.isActiveAt(records[i].keyId, entry.anchoredAt)) {
                results[i] = VerificationStatus.KEY_EXPIRED_AT_ANCHOR;
                continue;
            }

            // 3. Verificación criptográfica on-chain via ISignatureVerifier (ERC-7913)
            address verifier = $.keyRegistry.getVerifier(records[i].algorithmId);
            bytes memory pubKey = $.keyRegistry.getKey(records[i].keyId).publicKey;

            try ISignatureVerifier(verifier).verify(pubKey, messageToSign, fullSignatures[i])
                returns (bytes4 magic)
            {
                results[i] = (magic == ERC7913_MAGIC_VALUE)
                    ? VerificationStatus.VALID
                    : VerificationStatus.INVALID_SIGNATURE;
            } catch {
                // Verifier revirtió → algoritmo no soportado on-chain (ML-DSA, Ed25519...)
                results[i] = VerificationStatus.NOT_SUPPORTED_ONCHAIN;
            }
        }
    }

    // ── Consultas (view) ──────────────────────────────────────────────────────

    function exists(bytes32 eventHash) external view returns (bool) {
        return _getAuditRegistryStorage().entries[eventHash].anchoredAt != 0;
    }

    function getEntry(bytes32 eventHash) external view returns (AuditEntry memory) {
        AuditRegistryStorage storage $ = _getAuditRegistryStorage();
        AuditEntry memory entry = $.entries[eventHash];
        if (entry.anchoredAt == 0) revert EntryNotFound(eventHash);
        return entry;
    }

    function getSigners(bytes32 eventHash) external view returns (SignerRecord[] memory) {
        return _getAuditRegistryStorage().signers[eventHash];
    }

    function getEntryWithSigners(bytes32 eventHash)
        external view
        returns (AuditEntry memory entry, SignerRecord[] memory signers)
    {
        AuditRegistryStorage storage $ = _getAuditRegistryStorage();
        entry = $.entries[eventHash];
        if (entry.anchoredAt == 0) revert EntryNotFound(eventHash);
        signers = $.signers[eventHash];
    }

    function getEncoder() external view returns (IAuditEncoder) {
        return _getAuditRegistryStorage().encoder;
    }

    function getKeyRegistry() external view returns (IKeyRegistry) {
        return _getAuditRegistryStorage().keyRegistry;
    }
}
