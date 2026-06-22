# CTB Audit Service V1 — ISBE Diamond Modality 1

This repository contains the CTB Audit Service V1 adapted to the ISBE Diamond architecture.

The current version follows ISBE Diamond modality 1: the audit service logic and signature verification are covered by the Diamond flow. The ECDSA secp256k1 EIP-712 verification is performed natively inside `AuditServiceInternal`, instead of deploying a standalone verifier contract.

## What this repository contains

* `contracts/auditservice/`: CTB Audit Service V1 contracts.
* `contracts/constants/`: shared constants, storage slot, resolver/config IDs, roles and EIP-712 domain values.
* `contracts/example-hashtimestamp/`: inherited example from the ISBE template.
* `contracts/testwrapper/auditservice/`: concrete wrapper used by unit tests.
* `scripts/project/deployAuditService.ts`: deployment script for the unified Audit Service facet.
* `test/project.test.ts`: unit tests for the unified Audit Service.
* `isbe-network-case/`: local ISBE/Besu network inherited from the template.

## Architecture

The service is exposed through the ISBE Diamond/EIP-2535 flow.

Main contracts:

* `AuditServiceFacet.sol`: Diamond facet and introspection entry point.
* `AuditService.sol`: external API layer with RBAC and pause guards.
* `AuditServiceInternal.sol`: storage, business logic and native ECDSA verification.
* `IAuditService.sol`: public interface, events and custom errors.
* `AuditTypes.sol`: shared structs for schemas, algorithms, keys, envelopes and anchors.

The previous standalone verifier approach has been removed from productive contracts. There is no productive `ISignatureVerifier` or standalone `EcdsaSecp256k1Verifier` in the unified version.

## Native signature algorithm

Supported native algorithm:

```text
ECDSA_SECP256K1_EIP712
```

The public key is encoded as:

```text
abi.encode(address expectedSigner)
```

The signed payload is an EIP-712 `AuditEnvelope` bound to the deployed service verifying contract.

## Local setup

Install dependencies:

```bash
npm ci
```

Create `.env` from `.env_sample` and configure the local account:

```env
ACCOUNT_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
ACCOUNT_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
LOCALHOST_URL=http://localhost:8545
```

These credentials are public Hardhat development credentials. Do not use them in any real-value environment.

## Tests

Run:

```bash
npx hardhat clean
npx hardhat compile
npx hardhat test
```

Expected validation:

```text
45 passing
```

The test suite covers key lifecycle, timestamp-based activeness, O(1) signer lookup, tenant isolation, idempotency, schema and algorithm guards, envelope validation, EIP-712 binding, native ECDSA verification, pausing, RBAC and metadata.

## Deploy to local ISBE

Start the local ISBE/Besu network:

```bash
cd isbe-network-case
./startNetwork.sh
cd ..
```

Check the chain:

```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
```

Expected local ISBE chain ID:

```text
0x2b41
```

The ISBE Diamond governance address is:

```text
0x00000000000000000000000000000000000015BE
```

Deploy the Audit Service:

```bash
npx hardhat run ./scripts/project/deployAuditService.ts --network isbe
```

The script performs three steps:

1. Registers `AuditServiceFacet` as business logic in the ISBE Diamond.
2. Sets the use case configuration.
3. Deploys the Audit Service use case proxy.

## Current validation status

Validated locally with:

```bash
npm ci
npx hardhat clean
npx hardhat compile
npx hardhat test
npx hardhat run ./scripts/project/deployAuditService.ts --network isbe
```

Latest local deployment example:

```text
Diamond governance: 0x00000000000000000000000000000000000015BE
Implementation:    0xFe1767dAF1eC7306a807326442562Cd0d0529231
AuditService proxy: 0x01D01347D87e2DB248df9fD9D25bB5439e35e20C
```

## Notes for Windows / Git Bash

The local Besu network scripts use Docker bind mounts. On Windows with Git Bash, path conversion can break container paths such as `/opt/besu/config`.

The included network scripts normalize Docker mount paths with `cygpath -m` and protect Docker arguments with `MSYS2_ARG_CONV_EXCL="*"`.
