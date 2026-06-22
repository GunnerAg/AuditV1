# CTB Audit Service V1 — Modalidad 1 del Diamond de ISBE

Este repositorio contiene CTB Audit Service V1 adaptado a la arquitectura Diamond de ISBE.

La versión actual sigue la modalidad 1 de ISBE: la lógica del servicio de auditoría y la verificación de firmas quedan cubiertas por el flujo del Diamond. La verificación ECDSA secp256k1 EIP-712 se realiza de forma nativa dentro de `AuditServiceInternal`, sin desplegar un contrato verificador independiente.

## Contenido del repositorio

* `contracts/auditservice/`: contratos del CTB Audit Service V1.
* `contracts/constants/`: constantes compartidas, storage slot, resolver/config IDs, roles y dominio EIP-712.
* `contracts/example-hashtimestamp/`: ejemplo heredado de la plantilla ISBE.
* `contracts/testwrapper/auditservice/`: wrapper concreto usado por los tests unitarios.
* `scripts/project/deployAuditService.ts`: script de despliegue del Audit Service unificado.
* `test/project.test.ts`: tests unitarios del Audit Service unificado.
* `isbe-network-case/`: red local ISBE/Besu heredada de la plantilla.

## Arquitectura

El servicio se expone mediante el flujo Diamond/EIP-2535 de ISBE.

Contratos principales:

* `AuditServiceFacet.sol`: facet Diamond e introspección.
* `AuditService.sol`: capa externa con RBAC y pause guards.
* `AuditServiceInternal.sol`: storage, lógica de negocio y verificación ECDSA nativa.
* `IAuditService.sol`: interfaz pública, eventos y errores custom.
* `AuditTypes.sol`: structs compartidos para schemas, algoritmos, claves, envelopes y anchors.

El enfoque anterior con verificador externo se ha eliminado de los contratos productivos. En la versión unificada no existe un `ISignatureVerifier` productivo ni un `EcdsaSecp256k1Verifier` desplegable aparte.

## Algoritmo de firma nativo

Algoritmo soportado:

```text
ECDSA_SECP256K1_EIP712
```

La public key se codifica como:

```text
abi.encode(address expectedSigner)
```

El payload firmado es un `AuditEnvelope` EIP-712 ligado al contrato verificador desplegado.

## Instalación local

Instala dependencias:

```bash
npm ci
```

Crea `.env` desde `.env_sample` y configura la cuenta local:

```env
ACCOUNT_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
ACCOUNT_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
LOCALHOST_URL=http://localhost:8545
```

Estas credenciales son públicas de desarrollo Hardhat. No deben usarse en entornos con valor real.

## Tests

Ejecuta:

```bash
npx hardhat clean
npx hardhat compile
npx hardhat test
```

Resultado esperado:

```text
45 passing
```

La suite cubre ciclo de vida de claves, actividad basada en timestamp, lookup O(1) de signers, aislamiento por tenant, idempotencia, validaciones de schema y algoritmo, validación de envelopes, binding EIP-712, verificación ECDSA nativa, pausado, RBAC y metadata.

## Despliegue en ISBE local

Levanta la red local ISBE/Besu:

```bash
cd isbe-network-case
./startNetwork.sh
cd ..
```

Comprueba la chain:

```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
```

Chain ID esperado:

```text
0x2b41
```

La dirección del Diamond de gobierno de ISBE es:

```text
0x00000000000000000000000000000000000015BE
```

Despliega el Audit Service:

```bash
npx hardhat run ./scripts/project/deployAuditService.ts --network isbe
```

El script realiza tres pasos:

1. Registra `AuditServiceFacet` como business logic en el Diamond de ISBE.
2. Configura el caso de uso.
3. Despliega el proxy del Audit Service.

## Estado de validación

Validado localmente con:

```bash
npm ci
npx hardhat clean
npx hardhat compile
npx hardhat test
npx hardhat run ./scripts/project/deployAuditService.ts --network isbe
```

Ejemplo del último despliegue local:

```text
Diamond governance: 0x00000000000000000000000000000000000015BE
Implementation:    0xFe1767dAF1eC7306a807326442562Cd0d0529231
AuditService proxy: 0x01D01347D87e2DB248df9fD9D25bB5439e35e20C
```

## Nota para Windows / Git Bash

Los scripts de red local Besu usan bind mounts de Docker. En Windows con Git Bash, la conversión automática de rutas puede romper rutas internas del contenedor como `/opt/besu/config`.

Los scripts incluidos normalizan los mounts de Docker con `cygpath -m` y protegen los argumentos de Docker con `MSYS2_ARG_CONV_EXCL="*"`.
