// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

// solhint-disable max-line-length

/***** CTB AUDIT SERVICE V1 *****/

// Diamond storage position for CTB Audit Service V1.
// @dev Never change this value after deployment. Future versions must preserve this storage namespace.
bytes32 constant _PROJECT_STORAGE_POSITION =
    keccak256('isbe.customers.ctb.audit-service.v1.storage');

// ---------------------------------------------
// ---------------------------------------------
// ---- RBAC roles for CTB Audit Service V1 ----
// ---------------------------------------------
// ---------------------------------------------
// Generic admin/manager role kept for compatibility with the ISBE template.
bytes32 constant _PROJECT_ROLE =
    keccak256('isbe.customers.ctb.role.audit-service.manager');

// Role allowed to register and enable/disable schemas.
bytes32 constant _PROJECT_SCHEMA_MANAGER_ROLE =
    keccak256('isbe.customers.ctb.role.audit-service.schema-manager');

// Role allowed to register and enable/disable cryptographic algorithms.
bytes32 constant _PROJECT_ALGORITHM_MANAGER_ROLE =
    keccak256('isbe.customers.ctb.role.audit-service.algorithm-manager');

// Role allowed to register signer keys.
bytes32 constant _PROJECT_KEY_MANAGER_ROLE =
    keccak256('isbe.customers.ctb.role.audit-service.key-manager');

// Role allowed to revoke signer keys.
bytes32 constant _PROJECT_KEY_REVOKER_ROLE =
    keccak256('isbe.customers.ctb.role.audit-service.key-revoker');

// Role allowed to anchor audit events.
bytes32 constant _PROJECT_ANCHOR_ROLE =
    keccak256('isbe.customers.ctb.role.audit-service.anchor');

// ---------------------------------------------
// ---------------------------------------------
// ---- Resolver/configuration del template ----
// ---------------------------------------------
// ---------------------------------------------

// Business resolver key returned by ProjectFacet.businessIdIntrospection().
bytes32 constant _PROJECT_RESOLVER_KEY =
    keccak256('isbe.customers.ctb.audit-service.v1.resolver.key');

// Configuration id used by the ISBE deployment script.
bytes32 constant _PROJECT_CONFIG_ID =
    keccak256('isbe.customers.ctb.audit-service.v1.configuration');

// EIP-712 domain name for CTB Audit Service V1.
string constant _PROJECT_EIP712_NAME = 'CTB Audit Service';

// EIP-712 domain version for CTB Audit Service V1.
string constant _PROJECT_EIP712_VERSION = '1';

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