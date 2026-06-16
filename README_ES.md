# isbe-clients-template

Plantilla para desplegar contratos inteligentes propios en una red local de ISBE.

Este repositorio incluye todo lo necesario para: levantar una red ISBE local con Docker, escribir y compilar contratos Solidity, y desplegarlos en la red mediante el patrón Diamond (EIP-2535).

Para más información sobre ISBE, consulta la documentación oficial: [Red ISBE](https://docs.redisbe.com/documentation/)

---

## Requisitos previos

- [Node.js](https://nodejs.org/) >= 18
- [Docker](https://www.docker.com/) instalado y en ejecución
- [`jq`](https://stedolan.github.io/jq/) — procesador JSON usado por los scripts de red
  - macOS: `brew install jq`
  - Ubuntu/Debian: `apt-get install jq`

---

## Estructura del proyecto

```
contracts/
  constants/                   — constantes compartidas (roles, storage slots, config IDs)
  project-contracts/         — contratos de ejemplo: sustituir por los propios
  testwrapper/               — wrapper para tests unitarios
scripts/
  deployContracts.ts         — script de despliegue Diamond en tres pasos
isbe-network-case/           — entorno de red local ISBE (Docker + Besu)
  startNetwork.sh            — arranca la red
  stopNetwork.sh             — para la red
  QBFT-Network/              — datos de los nodos (claves, génesis, etc.)
```

---

## Instalación

```bash
npm install
```

Copia el archivo de variables de entorno y rellena los valores:

```bash
cp .env_sample .env
```

Edita `.env` con las credenciales de **Account #0 de Hardhat**:

```env
ACCOUNT_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
ACCOUNT_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
LOCALHOST_URL=http://localhost:8545
```

> Es necesario utilizar Account #0 porque es la cuenta pre-financiada en el génesis de la red local con permisos de administrador para el despliegue.
>
> ⚠️ Estas credenciales son públicas y solo válidas para desarrollo local. **Nunca las uses en mainnet ni en ningún entorno con valor real.**


---

## 1. Levantar la red local

Desde la carpeta `isbe-network-case`:

```bash
cd isbe-network-case
./startNetwork.sh
```

Esto levanta 4 nodos Besu con QBFT mediante Docker. Para comprobar que están corriendo:

```bash
docker ps
```

Para parar la red:

```bash
./stopNetwork.sh
```

---

## 2. Añadir los contratos propios

Los contratos de ejemplo en `contracts/project-contracts/` sirven como referencia para pruebas en local. A la hora de integrar los contratos propios hay dos opciones:

**Opción A — Renombrar los contratos propios para encajar en la estructura de ejemplo.** Renombra tus contratos a `ProjectFacet`, `ProjectInternal`, etc. De este modo el script de despliegue y los constants apenas necesitan cambios.

**Opción B — Sustituir la estructura entera.** Borra los contratos de ejemplo y coloca los tuyos con su propia nomenclatura. En este caso hay que actualizar también el script de despliegue y los constants para que los nombres coincidan.

En cualquier caso los pasos son:

1. Coloca tus contratos en `contracts/`
2. Actualiza `contracts/constants/constants.sol` con las constantes de tu proyecto (ver sección siguiente)
3. Actualiza el nombre del facet en `scripts/project/deployContracts.ts` (línea `artifacts.readArtifact('ProjectFacet')`)
4. Calcula y rellena las constantes del script de despliegue (ver sección siguiente)

En el fichero `Adaptacion.md` puedes encontrar más detalles sobre cómo adaptar tu código de smart contracts para que tengan la estructura del diamante de ISBE.

---

## 3. Definir el namespace y las constantes

Los contratos de ejemplo usan un namespace genérico en `contracts/constants/constants.sol`:

```solidity
bytes32 constant _PROJECT_STORAGE_POSITION = keccak256('isbe.customers.customer.project.storage');
bytes32 constant _PROJECT_ROLE             = keccak256('isbe.customers.customer.role.project.role');
bytes32 constant _PROJECT_RESOLVER_KEY     = keccak256('isbe.customers.customer.role.project.resolver.key');
bytes32 constant _PROJECT_CONFIG_ID        = keccak256('isbe.customers.customer.project.configuration');
```

Los términos `customer`, `project` y `role` son placeholders. En un despliegue real hay que sustituirlos por los valores propios del cliente: nombre de la empresa, nombre del proyecto y nombre del rol. Por ejemplo:

```solidity
bytes32 constant _ACME_STORAGE_POSITION = keccak256('isbe.customers.acme.invoicing.storage');
bytes32 constant _ACME_ROLE             = keccak256('isbe.customers.acme.role.invoicing.manager');
bytes32 constant _ACME_RESOLVER_KEY     = keccak256('isbe.customers.acme.role.invoicing.resolver.key');
bytes32 constant _ACME_CONFIG_ID        = keccak256('isbe.customers.acme.invoicing.configuration');
```

Una vez definido el namespace, hay que calcular los valores hash para el script de despliegue:

```typescript
const PROJECT_RESOLVER_KEY = '' // keccak256 del resolver key de tu facet
const PROJECT_CONFIG_ID = ''    // keccak256 del config ID de tu proyecto
```

Puedes calcularlos con Node.js:

```bash
node -e "const { ethers } = require('ethers'); console.log(ethers.keccak256(ethers.toUtf8Bytes('isbe.customers.acme.role.invoicing.resolver.key')))"
```

Los valores deben coincidir exactamente con los definidos en `contracts/constants/constants.sol`.

---

## 4. Compilar

```bash
npx hardhat compile
```

---

## 5. Desplegar

```bash
npx hardhat run scripts/project/deployContracts.ts --network isbe
```

El script realiza tres pasos automáticamente:

1. **`deploy`** — registra el bytecode de tu facet en el Diamond con el resolver key
2. **`setConfiguration`** — asocia el resolver key con el config ID
3. **`deployUseCase`** — despliega el proxy que enruta al facet registrado

Al finalizar muestra un resumen con las direcciones de la implementación y del proxy.

---

## Tests

```bash
npx hardhat test
```

Los tests usan `ProjectTestWrapper`, un contrato que extiende el facet con helpers de inicialización y pausa para pruebas unitarias aisladas, sin necesidad de infraestructura de gobernanza.

---

## Cómo funciona el patrón Diamond en ISBE

La red ISBE tiene un proxy Diamond en una dirección fija de génesis:

```
0x00000000000000000000000000000000000015BE
```

Este proxy enruta las llamadas a los facets registrados. Al desplegar un caso de uso no se despliega un contrato de forma directa — se registra la implementación en el Diamond y este crea el proxy. Eso significa que:

- La dirección del proxy la asigna el Diamond, no el deployer
- El storage del contrato persiste entre actualizaciones
- Para actualizar la lógica basta con registrar una nueva versión del bytecode (pasos 1 y 2) sin redesplegar el proxy

---

## Ejemplo: HashTimestamp

La carpeta `contracts/example-hashtimestamp/` contiene un caso de uso completo y funcional que sirve como referencia de cómo debería quedar un proyecto real adaptado a esta plantilla.

`HashTimestampFacet` es un facet que permite registrar hashes en blockchain junto con su timestamp. Una vez registrado un hash, queda sellado con la marca de tiempo del bloque y no puede volver a registrarse. Expone tres funciones: `timestampHash`, `exists` y `getTimestamp`.

La estructura del ejemplo sigue exactamente el mismo patrón que se espera de cualquier proyecto real:

```
contracts/
  constants/constants.sol                              — constantes del ejemplo añadidas al constants compartido
  example-hashtimestamp/
    IHashTimestamp.sol                             — interfaz pública
    HashTimestampInternal.sol                      — lógica y storage internos
    HashTimestamp.sol                              — contrato abstracto con las funciones externas
    HashTimestampFacet.sol                         — facet Diamond con introspección EIP-2535
  testwrapper/hashtimestamp/
    HashTimestampTestWrapper.sol                   — wrapper para tests unitarios
scripts/
  hashtimestamp/
    deployHashTimestamp.ts                         — script de despliegue del ejemplo
```

Para desplegar el ejemplo en la red local:

```bash
npx hardhat run scripts/hashtimestamp/deployHashTimestamp.ts --network isbe
```

Al adaptar esta plantilla a un proyecto propio, este ejemplo muestra concretamente qué hay que hacer en cada archivo: dónde definir el storage, cómo implementar la introspección EIP-2535, cómo añadir las constantes al constants, y cómo ajustar el script de despliegue con el namespace y los hashes correctos.

---

## Licencia

Apache-2.0