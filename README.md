# 🏥 CTB Audit Service - Immutable Smart Contracts

Este repositorio contiene la capa de anclaje inmutable (Blockchain) para el servicio SaaS de auditoría de CTB. La arquitectura está diseñada para actuar como un "Notario Digital Ciego", garantizando integridad matemática y cumplimiento normativo (GDPR/eIDAS) sin exponer datos sensibles on-chain.

## 🏗️ Arquitectura del Sistema

El sistema utiliza un patrón UUPS (Universal Upgradeable Proxy Standard) combinado con almacenamiento ERC-7201 (Namespaced Storage) para garantizar actualizaciones seguras a lo largo de los años sin colisión de memoria.

*   **`AuditEncoder.sol` (Inmutable):** Define el formato canónico EIP-712. Se despliega sin proxy para garantizar que los recibos históricos sean siempre verificables, independientemente de futuras actualizaciones del sistema.
*   **`KeyRegistry.sol` (Proxy UUPS):** Gestiona el ciclo de vida de los Audit Nodes de los clientes (registro, rotación y revocación de claves).
*   **`AuditRegistry.sol` (Proxy UUPS):** El orquestador de anclaje. Permite registrar firmas de forma individual o en `batch` y actúa como oráculo de verificación (ERC-7913).
*   **`EcdsaSecp256k1Verifier.sol`:** Motor criptográfico para verificar firmas estándar de Ethereum.

## 🔐 Privacidad y Cumplimiento (GDPR)

El Smart Contract **nunca** almacena datos originales ni hashes directos de los datos.
*   **On-chain:** Solo se almacena un `eventHash` generado off-chain mediante `HMAC-SHA256(tenantKey, rawDataHash)`.
*   **Derecho al olvido:** Si un paciente o cliente exige la eliminación de sus datos, la destrucción de la `tenantKey` rompe matemáticamente el vínculo entre la blockchain y el dato original.

## 🛠️ Estándares Implementados
*   **EIP-712:** Firmas estructuradas legibles.
*   **ERC-7913:** Verificación de firmas agnóstica de algoritmo (preparado para Post-Quantum/Lattice y ZK Coprocessors).
*   **ERC-7201:** Namespaced Storage para seguridad en proxies.
*   **EIP-1822 / EIP-1967:** Patrón UUPS Proxy.

## 🧪 Testing
[Instrucciones para ejecutar la suite de tests...]