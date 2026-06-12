// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { Key } from "./AuditTypes.sol";
import { IKeyRegistry } from "./IKeyRegistry.sol";

/**
 * @title KeyRegistry
 * @notice Registro de claves públicas y algoritmos de firma.
 * @dev UUPS upgradeable. ERC-7201 namespaced storage. OZ v5.x.
 *
 *      Storage slot: keccak256(abi.encode(uint256(keccak256("ctb.storage.KeyRegistry")) - 1)) & ~bytes32(uint256(0xff))
 *      Verificar con Foundry antes de deploy:
 *        bytes32(uint256(keccak256(abi.encode(uint256(keccak256("ctb.storage.KeyRegistry")) - 1))) & ~uint256(0xff))
 */
contract KeyRegistry is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    IKeyRegistry
{
    // ── Roles ─────────────────────────────────────────────────────────────────
    bytes32 public constant ALGO_MANAGER_ROLE = keccak256("ALGO_MANAGER_ROLE");
    bytes32 public constant KEY_MANAGER_ROLE  = keccak256("KEY_MANAGER_ROLE");
    bytes32 public constant REVOKER_ROLE      = keccak256("REVOKER_ROLE");

    // ── ERC-7201 Namespaced Storage ───────────────────────────────────────────
    // keccak256(abi.encode(uint256(keccak256("ctb.storage.KeyRegistry")) - 1)) & ~bytes32(uint256(0xff))
    // Valor verificado en test: erc7201Slot("ctb.storage.KeyRegistry") == 0x656e54d0...
    bytes32 private constant KeyRegistryStorageLocation =
        0x656e54d04fc08734d2dbd2086fd3733db9e12442b7853c28526ffb82c6230f00;

    struct KeyRegistryStorage {
        mapping(bytes32 => Key)     keys;
        mapping(bytes32 => address) algorithmVerifiers;
    }

    function _getKeyRegistryStorage() private pure returns (KeyRegistryStorage storage $) {
        assembly { $.slot := KeyRegistryStorageLocation }
    }

    // ── Inicialización ────────────────────────────────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(address defaultAdmin) public initializer {
        __AccessControl_init();
        // __UUPSUpgradeable_init() no existe en OZ v5 — no es necesario llamarlo.
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // ── Versioning ────────────────────────────────────────────────────────────

    /// @notice Versión de esta implementación. Sobreescribir en V2 con "2", etc.
    function version() external pure virtual returns (string memory) { return "1"; }

    // ── Gestión de algoritmos (ALGO_MANAGER_ROLE) ─────────────────────────────

    function registerAlgorithm(bytes32 algorithmId, address verifier)
        external onlyRole(ALGO_MANAGER_ROLE)
    {
        KeyRegistryStorage storage $ = _getKeyRegistryStorage();
        if ($.algorithmVerifiers[algorithmId] != address(0)) revert AlgorithmAlreadyRegistered(algorithmId);
        $.algorithmVerifiers[algorithmId] = verifier;
        emit AlgorithmRegistered(algorithmId, verifier);
    }

    function updateAlgorithmVerifier(bytes32 algorithmId, address newVerifier)
        external onlyRole(ALGO_MANAGER_ROLE)
    {
        KeyRegistryStorage storage $ = _getKeyRegistryStorage();
        if ($.algorithmVerifiers[algorithmId] == address(0)) revert AlgorithmNotFound(algorithmId);
        address oldVerifier = $.algorithmVerifiers[algorithmId];
        $.algorithmVerifiers[algorithmId] = newVerifier;
        emit AlgorithmVerifierUpdated(algorithmId, oldVerifier, newVerifier);
    }

    // ── Gestión de claves (KEY_MANAGER_ROLE / REVOKER_ROLE) ───────────────────

    function registerKey(
        bytes32        keyId,
        bytes32        algorithmId,
        bytes calldata publicKey,
        bytes32        tenantId,
        uint64         expiresAt
    ) external onlyRole(KEY_MANAGER_ROLE) {
        KeyRegistryStorage storage $ = _getKeyRegistryStorage();

        if ($.keys[keyId].registeredAt != 0)             revert KeyAlreadyExists(keyId);
        if ($.algorithmVerifiers[algorithmId] == address(0)) revert AlgorithmNotSupported(algorithmId);
        if (publicKey.length == 0)                        revert InvalidPublicKey(keyId);
        if (expiresAt != 0 && expiresAt <= block.timestamp) revert InvalidExpiresAt(keyId, expiresAt);

        $.keys[keyId] = Key({
            keyId:       keyId,
            algorithmId: algorithmId,
            publicKey:   publicKey,
            tenantId:    tenantId,
            registeredAt: uint64(block.timestamp),
            expiresAt:   expiresAt,
            revokedAt:   0
        });

        emit KeyRegistered(keyId, tenantId, algorithmId, publicKey, uint64(block.timestamp), expiresAt);
    }

    function revokeKey(bytes32 keyId) external onlyRole(REVOKER_ROLE) {
        KeyRegistryStorage storage $ = _getKeyRegistryStorage();
        if ($.keys[keyId].registeredAt == 0) revert KeyNotFound(keyId);
        if ($.keys[keyId].revokedAt != 0)    revert KeyAlreadyRevoked(keyId);

        $.keys[keyId].revokedAt = uint64(block.timestamp);
        emit KeyRevoked(keyId, $.keys[keyId].tenantId, uint64(block.timestamp), msg.sender);
    }

    // ── Consultas (public / view) ─────────────────────────────────────────────

    function getKey(bytes32 keyId) external view returns (Key memory) {
        KeyRegistryStorage storage $ = _getKeyRegistryStorage();
        Key memory key = $.keys[keyId];
        if (key.registeredAt == 0) revert KeyNotFound(keyId);
        return key;
    }

    /// @dev Usa la función interna para evitar la penalización del CALL opcode (~2100 gas)
    ///      que causaría `this.isActiveAt()`.
    function isActive(bytes32 keyId) external view returns (bool) {
        KeyRegistryStorage storage $ = _getKeyRegistryStorage();
        Key memory key = $.keys[keyId];
        if (key.registeredAt == 0)                                       return false;
        if (key.revokedAt != 0)                                          return false;
        if (key.expiresAt != 0 && key.expiresAt <= uint64(block.timestamp)) return false;
        return true;
    }

    function isActiveAt(bytes32 keyId, uint64 timestamp) external view returns (bool) {
        return _isActiveAt(keyId, timestamp);
    }

    /// @dev Lógica interna compartida. Verifica las tres condiciones:
    ///      1. Clave registrada antes o en el timestamp dado.
    ///      2. No revocada en o antes del timestamp.
    ///      3. No expirada en o antes del timestamp.
    function _isActiveAt(bytes32 keyId, uint64 timestamp) internal view returns (bool) {
        KeyRegistryStorage storage $ = _getKeyRegistryStorage();
        Key memory key = $.keys[keyId];
        if (key.registeredAt == 0 || key.registeredAt > timestamp) return false;
        if (key.revokedAt != 0   && key.revokedAt  < timestamp)   return false; // < estricto
        if (key.expiresAt != 0   && key.expiresAt  <= timestamp)  return false;
        return true;
    }

    function getVerifier(bytes32 algorithmId) external view returns (address) {
        return _getKeyRegistryStorage().algorithmVerifiers[algorithmId];
    }
}