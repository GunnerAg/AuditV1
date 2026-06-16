# CTB Audit Service V1 — ISBE Diamond Integration

This repository is an adaptation of the official ISBE client template, not a project created from scratch. It keeps the infrastructure and local-network workflow from `red-isbe/isbe-clients-template` and adds the `CTB Audit Service V1` smart contracts, deployment script and end-to-end validation flow.

Template source: https://github.com/red-isbe/isbe-clients-template

ISBE Diamond implementation guide: https://docs.redisbe.com/documentation/smart-contracts/guias-practicas/implementacion-diamond/

## What this repository contains

- `contracts/example-hashtimestamp/`: inherited example from the ISBE template.
- `contracts/project-contracts/`: CTB Audit Service V1 contracts.
- `scripts/project/`: deploy and E2E validation scripts for the CTB service.
- `test/project.test.ts`: unit tests for CTB Audit Service V1.
- `isbe-network-case/`: local ISBE/Besu network inherited from the template.

## Added CTB contracts

- `contracts/project-contracts/ProjectFacet.sol`: ISBE Diamond facet exposing Audit Service selectors and introspection.
- `contracts/project-contracts/Project.sol`: external API layer with RBAC and pause guards.
- `contracts/project-contracts/ProjectInternal.sol`: internal storage and business logic.
- `contracts/project-contracts/IProject.sol`: public interface, events and custom errors.
- `contracts/project-contracts/AuditTypes.sol`: shared structs for schemas, algorithms, keys, envelopes and anchors.
- `contracts/project-contracts/ISignatureVerifier.sol`: verifier interface used by registered algorithms.
- `contracts/project-contracts/verifiers/EcdsaSecp256k1Verifier.sol`: ECDSA secp256k1 verifier for EIP-712 digests.
- `contracts/constants/constants.sol`: CTB roles, resolver/config IDs, storage slot and EIP-712 domain constants.

`EcdsaSecp256r1Verifier.sol` is not present in this repository.

## Architecture

The service follows the ISBE Diamond/EIP-2535 pattern. `ProjectFacet` declares the selectors exposed through the Diamond proxy, while `ProjectInternal` owns the Audit Service logic and stores state in a fixed `ProjectStorage` slot.

The CTB resolver and configuration identifiers are namespaced:

- resolver key: `isbe.customers.ctb.audit-service.v1.resolver.key`
- config ID: `isbe.customers.ctb.audit-service.v1.configuration`

EIP-712 domain:

- name: `CTB Audit Service`
- version: `1`

The Hardhat Solidity configuration targets `istanbul`.

## Audit Service V1 functionality

- Schema registry.
- Algorithm/verifier registry.
- Key registry and revocation.
- Timestamp-based key activeness.
- Tenant isolation.
- N signatures per event.
- Audit anchoring.
- On-chain signature verification.
- Custom errors.
- RBAC.
- Pausable flows.

## Local setup

```powershell
npm install
```

Create `.env` from `.env_sample` for local development:

```env
ACCOUNT_ADDRESS=...
ACCOUNT_PRIVATE_KEY=...
LOCALHOST_URL=http://localhost:8545
PROJECT_PROXY=
```

`PROJECT_PROXY` is optional. If it is omitted, `scripts/project/validateE2E.ts` reads `deployments/isbe-audit-latest.json`.

## Tests

```powershell
npx hardhat test test/project.test.ts
```

Expected result:

```text
Compiled 69 Solidity files successfully (evm target: istanbul).
45 passing
```

Conceptual coverage includes key lifecycle, O(1) signer lookup, tenant isolation, idempotency, schema and algorithm guards, envelope validation, EIP-712 binding, pausing, RBAC and metadata.

## Deploy to local ISBE

```powershell
npx hardhat run scripts/project/deployContracts.ts --network isbe
```

The script checks platform roles, ensures governance facets for local ISBE bootstrap, registers `ProjectFacet`, sets the CTB configuration, deploys the use case proxy and writes `deployments/isbe-audit-latest.json`.

Example output:

```text
[OK] Platform roles confirmed
[OK] Platform governance facets confirmed
[OK] ProjectFacet version X registered
[OK] Configuration set, version Y
[OK] Use case proxy deployed at 0x...
```

`deployments/isbe-audit-latest.json` is a generated local artifact and is ignored by git.

## E2E validation

```powershell
npx hardhat run scripts/project/validateE2E.ts --network isbe
```

Proxy resolution order:

1. `PROJECT_PROXY`
2. `deployments/isbe-audit-latest.json`

The validation deploys `EcdsaSecp256k1Verifier`, registers a unique algorithm/schema/key, builds an `AuditEnvelope`, checks the EIP-712 digest, signs with raw ECDSA secp256k1, anchors the event, reads anchor/signers, checks `verifySignature == true` and runs negative tests for missing anchor role, invalid signature and disabled algorithm.

## Quickstart

```powershell
npm install
npx hardhat clean
npx hardhat test test/project.test.ts
npx hardhat run scripts/project/deployContracts.ts --network isbe
npx hardhat run scripts/project/validateE2E.ts --network isbe
```

## Troubleshooting

- `validateE2E.ts` uses an old proxy: remove the stale `PROJECT_PROXY` value or rerun deploy to regenerate `deployments/isbe-audit-latest.json`.
- `setConfiguration` reverts with `0x`: in local ISBE, governance facets may be missing; `deployContracts.ts` ensures them automatically.
- `registerAlgorithm` reverts: usually the target proxy is wrong or the signer lacks roles on that proxy.
- `AlgorithmAlreadyRegistered` / `SchemaAlreadyRegistered`: use unique IDs per run or make the E2E explicitly idempotent. The included E2E generates unique IDs.
- `npm audit` reports vulnerabilities: do not block local development on this alone; review before production use.
- SPDX warning in `HashTimestampStandalone.sol`: corrected with `Apache-2.0`.

## Current validation status

Validated on local ISBE/Besu, chainId `11073`, Diamond/factory `0x00000000000000000000000000000000000015BE`.

- `npx hardhat clean`: passed.
- `npx hardhat test test/project.test.ts`: passed, 45 passing, 69 Solidity files compiled with EVM target `istanbul`.
- `npx hardhat run scripts/project/deployContracts.ts --network isbe`: passed.
- Latest generated proxy: `0x33619a2035E13f9d247D5c886DB61bF918EDCB92`.
- `deployments/isbe-audit-latest.json`: generated with that proxy, business version `11`, configuration version `8`.
- `npx hardhat run scripts/project/validateE2E.ts --network isbe`: passed using `deployments/isbe-audit-latest.json`.
