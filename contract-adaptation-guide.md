# Adapting legacy contracts to the Diamond Pattern

When adapting an existing contract to the `Project*` schema you must adjust its architecture, variable storage and introspection — not just copy the code.

## 1) Define which functions will be externally callable

Before writing any code, decide exactly which functions will be `external` in the facet.

- Define those functions in `IProject.sol`.
- `Project.sol` must implement exactly those same functions with the same Keccak256 signature (using `override`).
- Do not leave extra external functions in `Project.sol` that are not in `IProject.sol`, to avoid ABI inconsistencies.
- If you change the parameter order in `IProject.sol`, update `Project.sol` and the corresponding tests as well.

## 2) Separate responsibilities by layer (mandatory)

Follow the same structure as in `example-hashtimestamp`:

- `IProject.sol`: The public interface (defines events + external functions).
- `ProjectInternal.sol`: The storage and internal logic.
- `Project.sol`: The external layer with access controls (`whenNotPaused`, `onlyRole(_PROJECT_ROLE)`) that delegates to the internal functions defined in `ProjectInternal.sol`.
- `ProjectFacet.sol`: EIP-2535 introspection (`interfacesIntrospection`, `businessIdIntrospection`, `selectorsIntrospection`).

## 3) Redefine variable storage to avoid storage collisions (Namespaced Storage Layout)

If your smart contract has variables (`uint256 uid`, mappings…), do not declare them directly in the facet. Use a struct instead.

In `ProjectInternal.sol`:

- Create `struct ProjectStorage` with all the state. All variables are defined one after another as struct fields.

Example:

Before:
```solidity
uint256 uid;
mapping(uint256 => bytes32) public example;
mapping(bytes32 => uint256) public example2;
```

After:
```solidity
struct ProjectStorage {
    uint256 uid;
    mapping(uint256 => bytes32) example;
    mapping(bytes32 => uint256) example2;
}
```

- Implement the `_projectStorage()` function with the fixed slot `_PROJECT_STORAGE_POSITION`.
- All reads and writes must be done through `_projectStorage()`. For example, to write a new value with key `1` in the `example` mapping: `_projectStorage().example[1] = ...`

This avoids storage collisions between facets and allows safe upgrades.

## 4) Do not use constructors to initialise variable state

In Diamond/facets you must not rely on the constructor to initialise the logical state of variables (e.g. setting `uid = 1` in the constructor).

Instead:

- Initialise lazily inside the function that needs it (e.g. on the first action).
- If `uid` must start at 1, increment it before saving, for example.

## 5) Implement `_implementedInterfaces()` in `Project.sol`

As defined in the `HashTimestamp.sol` example:

`ProjectFacet.interfacesIntrospection()` calls `_implementedInterfaces()`.

Therefore `Project.sol` must implement that method and return at least:

- `type(IProject).interfaceId`

This is already included in the `Project.sol` of this repository, but double-check just in case.

## 6) Fill `selectorsIntrospection()` with all external functions

In `ProjectFacet.sol`, the selector list must match 1-to-1 with the final external API of `Project`.

- Set `selectorsLength` to the total number of included functions. In `HashTimestampFacet.sol` there are 3.
- Include `this.<fn>.selector` for each external function.
- If you forget one, the facet may not be discoverable or registered correctly.

## 7) Keep full event consistency (signature + indexed + parameter order)

If you declare events in the interface or in the internal layer, they must match completely:

- Same name
- Same parameter order
- Same `indexed` parameters

Otherwise it can cause ABI confusion or indexing issues in the project, even if it compiles.

## 8) Maintain the ISBE network security model

In `Project.sol`, make sure to apply the ISBE Diamond guards:

- `whenNotPaused`
- `onlyRole(_PROJECT_ROLE)`

Do not use `Ownable` (typical of OpenZeppelin contracts) as the main role control mechanism.

## 9) Before deploying, check:

- `IProject` and `Project` have identical functions (same function signatures).
- `_implementedInterfaces()` exists in `Project`.
- `selectorsIntrospection()` contains all external functions.
- There is no constructor with state initialisation for variables.
- All variable state is managed through `ProjectStorage` + `_projectStorage()` with a struct.
- Running `npx hardhat compile` compiles without errors.
