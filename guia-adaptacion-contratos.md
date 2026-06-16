# Adaptación de contratos "legacy" al Patrón Diamante

Cuando vayas a realizar la adaptación de un contrato ya existente al esquema definido en `Project*` debes ajustar su arquitectura, almacenamiento de variables e introspección; no solamente copiar el código.

## 1) Definir qué funciones seran callable de manera externa

Antes de escribir código, decide exactamente qué funciones serán external en el facet.

- Define esas funciones en `IProject.sol`.
- `Project.sol` debe implementar exactamente esas mismas funciones, con la misma firma Keccak256 (se hace `override`).
- No dejes funciones externas "extra" en `Project.sol` que no estén en `IProject.sol` para evitar incoherencias en el ABI.
- Si cambias el orden de los parámetros en la interfaz `IProject.sol`, actualiza también `Project.sol` y los tests correspondientes.

## 2) Separa las responsabilidades por capa (obligatorio)

Sigue la misma estructura que en `example-hashtimestamp`:

- `IProject.sol`: Es la interfaz pública (define eventos + funciones externas).
- `ProjectInternal.sol`: Es el storage y la lógica interna.
- `Project.sol`: Es la capa externa con controles de acceso (`whenNotPaused`, `onlyRole(_PROJECT_ROLE)`) que delega en las funciones internas definidas en `ProjectInternal.sol`.
- `ProjectFacet.sol`: Uso de Introspection EIP-2535 (`interfacesIntrospection`, `businessIdIntrospection`, `selectorsIntrospection`).

## 3) Redefine el storage de variables para evitar colisiones de almacenamiento (Namespaced Storage Layout)

Si tu smart contract tiene variables (`uint256 uid`, mappings...), no las declares directamente en el facet. En su lugar emplea struct:

En `ProjectInternal.sol`:

- Crea `struct ProjectStorage` con todo el estado. Aqui se definen todas las variables una tras otra como componentes del struct.

Ejemplo:

Antes 
```
uint256 uid;
mapping (uint256 => bytes32) public ejemplo;
mapping (bytes32 => uint256) public ejemplo2;
``` 

Después:
```
struct ProjectStorage {
    uint256 uid;
    mapping (uint256 => bytes32) ejemplo;
    mapping (bytes32 => uint256) ejemplo2;
}
```
- Implementa la función `_projectStorage()` con el slot fijo `_PROJECT_STORAGE_POSITION`.
- Todas las lecturas y escrituras deben realizarse, por lo tanto, mediante `_projectStorage()`. Por ejemplo, para escribir un nuevo valor con la clave '1' en el mapping `ejemplo` de antes, se haría así: `_projectStorage().ejemplo[1] = ...`

Esto evita colisiones de almacenamiento entre facets y permite llevar a cabo upgrades de manera segura.


## 4) No uses constructores para inicializar estados de variables

En Diamond/facets no debes depender del constructor para inicializar el estado lógico de las variables empleadas (por ejemplo, incluir en el constructor que `uid = 1`).

En su lugar es recomendado:

- Realizar la inicialización de manera implícita en la función que lo necesita (por ejemplo, al realizar una acción por primera vez).
- Si `uid` debe empezar en 1 haz, por ejemplo, el incremento a +1 previamente al guardado.

## 5) Implementa `_implementedInterfaces()` en `Project.sol`

Al igual que se define en el ejemplo `HashTimestamp.sol`:

`ProjectFacet.interfacesIntrospection()` llama a `_implementedInterfaces()`.

Por tanto `Project.sol` debe implementar ese método y devolver al menos:

- `type(IProject).interfaceId`

En el fichero Project.sol de este repositorio ya viene, pero revisa por si no fuera el caso.

## 6) Rellena `selectorsIntrospection()` con todas las funciones externas

En `ProjectFacet.sol`, la lista de selectores debe coincidir 1 a 1 con la API externa final de `Project`.

- Ajusta `selectorsLength` al número total de funciones incluidas. Puedes ver que en `HashTimestampFacet.sol` son 3.
- Incluye `this.<fn>.selector` para cada función externa.
- Si olvidas uno, puede que el facet no pueda descubrirlo o registrarse correctamente.

## 7) Mantén coherencia total de eventos (firma + indexed + orden de parámetros)

Si declaras eventos en la interfaz o en la capa interna, estos deben coincidir completamente:

- Mismo nombre
- Mismo orden de parámetros
- Mismos parámetros `indexed`

Sino, puede generar confusiones en el ABI o en la indexación del proyecto, incluso aunque compile.


## 8) Mantén el modelo de seguridad de la red ISBE

En `Project.sol`, asegúrate de aplicar los controles/guards del diamante de ISBE:

- `whenNotPaused`
- `onlyRole(_PROJECT_ROLE)`

No uses `Ownable` (típico de contratos que emplean Openzeppelin) como mecanismo principal de control por roles.

## 10) Antes de desplegar comprueba:

- `IProject` y `Project` tienen funciones idénticas (misma firma de función).
- `_implementedInterfaces()` existe en `Project`.
- `selectorsIntrospection()` contiene todas las funciones external.
- No hay constructor con inicialización de estado para los parámetros.
- Todo el estado de variables se gestiona mediante `ProjectStorage` + `_projectStorage()` con struct.
- Ejecutando `npx hardhat compile` se compila sin errores.