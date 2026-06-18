// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

// solhint-disable max-line-length

/***** INSURECHAIN AUDIT SERVICE V1 *****/

// Diamond storage position for Insurechain Audit Service V1.
// @dev Never change this value after deployment. Future versions must preserve this storage namespace.
// node -e "const { ethers } = require('ethers'); console.log(ethers.keccak256(ethers.toUtf8Bytes('isbe.customers.insurechain.auditService.storage.position')))"
bytes32 constant _AUDIT_SERVICE_STORAGE_POSITION =
    keccak256('isbe.customers.insurechain.auditService.storage.position');

// ---------------------------------------------------------
// ---- RBAC roles for Insurechain Audit Service V1 --------
// ---------------------------------------------------------

// Generic admin/manager role.
// node -e "const { ethers } = require('ethers'); console.log(ethers.keccak256(ethers.toUtf8Bytes('isbe.customers.insurechain.auditService.project.role')))"
bytes32 constant _AUDIT_SERVICE_ROLE =
    keccak256('isbe.customers.insurechain.auditService.project.role');

// Role allowed to register and enable/disable schemas.
// node -e "const { ethers } = require('ethers'); console.log(ethers.keccak256(ethers.toUtf8Bytes('isbe.customers.insurechain.auditService.project.role.schemaManager')))"
bytes32 constant _AUDIT_SERVICE_SCHEMA_MANAGER_ROLE =
    keccak256('isbe.customers.insurechain.auditService.project.role.schemaManager');

// Role allowed to register and enable/disable cryptographic algorithms.
// node -e "const { ethers } = require('ethers'); console.log(ethers.keccak256(ethers.toUtf8Bytes('isbe.customers.insurechain.auditService.project.role.algorithmManager')))"
bytes32 constant _AUDIT_SERVICE_ALGORITHM_MANAGER_ROLE =
    keccak256('isbe.customers.insurechain.auditService.project.role.algorithmManager');

// Role allowed to register signer keys.
// node -e "const { ethers } = require('ethers'); console.log(ethers.keccak256(ethers.toUtf8Bytes('isbe.customers.insurechain.auditService.project.role.keyManager')))"
bytes32 constant _AUDIT_SERVICE_KEY_MANAGER_ROLE =
    keccak256('isbe.customers.insurechain.auditService.project.role.keyManager');

// Role allowed to revoke signer keys.
// node -e "const { ethers } = require('ethers'); console.log(ethers.keccak256(ethers.toUtf8Bytes('isbe.customers.insurechain.auditService.project.role.keyRevoker')))"
bytes32 constant _AUDIT_SERVICE_KEY_REVOKER_ROLE =
    keccak256('isbe.customers.insurechain.auditService.project.role.keyRevoker');

// Role allowed to anchor audit events.
// node -e "const { ethers } = require('ethers'); console.log(ethers.keccak256(ethers.toUtf8Bytes('isbe.customers.insurechain.auditService.project.role.anchor')))"
bytes32 constant _AUDIT_SERVICE_ANCHOR_ROLE =
    keccak256('isbe.customers.insurechain.auditService.project.role.anchor');

// ---------------------------------------------------------
// ---- Resolver / configuration ---------------------------
// ---------------------------------------------------------

// Business resolver key returned by AuditServiceFacet.businessIdIntrospection().
// node -e "const { ethers } = require('ethers'); console.log(ethers.keccak256(ethers.toUtf8Bytes('isbe.customers.insurechain.auditService.resolver.key')))"
bytes32 constant _AUDIT_SERVICE_RESOLVER_KEY =
    keccak256('isbe.customers.insurechain.auditService.resolver.key');

// Configuration id used by the ISBE deployment script.
// node -e "const { ethers } = require('ethers'); console.log(ethers.keccak256(ethers.toUtf8Bytes('isbe.customers.insurechain.auditService.config.id')))"
bytes32 constant _AUDIT_SERVICE_CONFIG_ID =
    keccak256('isbe.customers.insurechain.auditService.config.id');

// ---------------------------------------------------------
// ---- EIP-712 --------------------------------------------
// ---------------------------------------------------------

string constant _AUDIT_SERVICE_EIP712_NAME = 'Insurechain Audit Service';
string constant _AUDIT_SERVICE_EIP712_VERSION = '1';

// ---------------------------------------------------------
// ---- Supported algorithm identifiers --------------------
// ---------------------------------------------------------

// Native ECDSA secp256k1 algorithm supported by AuditServiceInternal.
// publicKey encoding: abi.encode(address expectedSigner) — 32 bytes.
bytes32 constant _AUDIT_SERVICE_ECDSA_ALGORITHM_ID =
    keccak256('ECDSA_SECP256K1_EIP712');

// solhint-enable max-line-length

/***** TEMPLATE EXAMPLE COMPATIBILITY *****/

bytes32 constant _HASH_TIMESTAMP_STORAGE_POSITION =
    keccak256('isbe.examples.hash-timestamp.storage');

bytes32 constant _HASH_TIMESTAMP_ROLE =
    keccak256('isbe.examples.hash-timestamp.role');

bytes32 constant _HASH_TIMESTAMP_RESOLVER_KEY =
    keccak256('isbe.examples.hash-timestamp.resolver.key');

bytes32 constant _HASH_TIMESTAMP_CONFIG_ID =
    keccak256('isbe.examples.hash-timestamp.configuration');