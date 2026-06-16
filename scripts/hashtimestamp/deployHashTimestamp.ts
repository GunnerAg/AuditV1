import { ethers, artifacts } from 'hardhat'
import { Interface, Signer, TransactionReceipt } from 'ethers'
import { readFileSync } from 'fs'
import { join } from 'path'

// --- Constants ---------------------------------------------------------------

/** ISBE Diamond proxy (genesis) - EIP-2535 governance entry point */
const DIAMOND = '0x00000000000000000000000000000000000015BE'

/**
 * keccak256('isbe.contracts.hash.timestamp.resolver.key')
 * Value returned by businessIdIntrospection() in HashTimestampFacet.
 *
 * node -e "const { ethers } = require('ethers'); console.log(ethers.keccak256(ethers.toUtf8Bytes('isbe.contracts.hash.timestamp.resolver.key')))"
 */
const HASH_TIMESTAMP_RESOLVER_KEY =
    '0xf4e751bf7e74c25f287942d8743e3d0fdfb08f29556e786178a50e2d69dc403a'

/**
 * keccak256('isbe.contracts.hash.timestamp.configuration')
 * Defined in contracts/commons/commons.sol as _HASH_TIMESTAMP_CONFIG_ID.
 *
 * node -e "const { ethers } = require('ethers'); console.log(ethers.keccak256(ethers.toUtf8Bytes('isbe.contracts.hash.timestamp.configuration')))"
 */
const HASH_TIMESTAMP_CONFIG_ID =
    '0xc8af69e11135d8d65c33a823012345537caa20f120dd748a791a4925bdd4d00b'

// --- Helpers -----------------------------------------------------------------

function getIsbeFactoryInterface(): Interface {
    const abiPath = join(
        __dirname,
        '../../node_modules/@red-isbe/isbe-contracts/artifacts/contracts/factory/IIsbeFactory.sol/IIsbeFactory.json'
    )
    const { abi } = JSON.parse(readFileSync(abiPath, 'utf8')) as { abi: any[] }
    return new ethers.Interface(abi)
}

function getEventFromReceipt(
    eventName: string,
    receipt: TransactionReceipt,
    iface: Interface
) {
    for (const log of receipt.logs) {
        try {
            const parsed = iface.parseLog(log)
            if (parsed?.name === eventName) return parsed
        } catch {
            // log from another contract, ignore
        }
    }
    throw new Error(
        `Event '${eventName}' not found in receipt (block ${receipt.blockNumber})`
    )
}

// --- Deployment steps --------------------------------------------------------

async function deployBusinessLogic(
    businessId: string,
    bytecode: string,
    factory: string,
    signer: Signer,
    iface: Interface
): Promise<{ businessAddress: string; version: string }> {
    console.log('Sending deployBusinessLogic transaction...')
    const data = iface.encodeFunctionData('deploy', [businessId, bytecode])
    const tx = await signer.sendTransaction({ to: factory, data, gasLimit: 25_000_000 })
    console.log('   Transaction submitted:', tx.hash)
    console.log('Waiting for transaction to be mined...')
    const receipt = await tx.wait()
    if (!receipt || receipt.status !== 1)
        throw new Error('deployBusinessLogic transaction failed or was reverted')
    const event = getEventFromReceipt('Deployed', receipt, iface)
    const { businessAddress, version } = event.args
    return { businessAddress, version: version.toString() }
}

async function setConfig(
    configId: string,
    businessId: string,
    factory: string,
    signer: Signer,
    iface: Interface
): Promise<{ version: string }> {
    console.log('Sending setConfiguration transaction...')
    const data = iface.encodeFunctionData('setConfiguration', [
        configId,
        [{ businessId, version: 1 }],
    ])
    const tx = await signer.sendTransaction({ to: factory, data, gasLimit: 25_000_000 })
    console.log('   Transaction submitted:', tx.hash)
    console.log('Waiting for transaction to be mined...')
    const receipt = await tx.wait()
    if (!receipt || receipt.status !== 1)
        throw new Error('setConfiguration transaction failed or was reverted')
    const event = getEventFromReceipt('ConfigurationSet', receipt, iface)
    const { version } = event.args
    return { version: version.toString() }
}

async function deployUseCase(
    configId: string,
    factory: string,
    signer: Signer,
    iface: Interface
): Promise<{ proxy: string }> {
    console.log('Sending deployUseCase transaction...')
    const data = iface.encodeFunctionData('deployUseCase', [
        configId,
        0,     // version (0 = latest)
        [],    // rbacs
        false, // initPause
        [],    // initBusinessIds
        [],    // initData
    ])
    const tx = await signer.sendTransaction({ to: factory, data, gasLimit: 25_000_000 })
    console.log('   Transaction submitted:', tx.hash)
    console.log('Waiting for transaction to be mined...')
    const receipt = await tx.wait()
    if (!receipt || receipt.status !== 1)
        throw new Error('deployUseCase transaction failed or was reverted')
    const event = getEventFromReceipt('UseCaseDeployed', receipt, iface)
    const { proxy } = event.args
    return { proxy }
}

// --- Main --------------------------------------------------------------------

async function main() {
    const [signer] = await ethers.getSigners()
    console.log('Deploying with account:', signer.address)

    const network = await ethers.provider.getNetwork()
    console.log('Network: isbe | Chain ID:', network.chainId.toString())
    console.log('Diamond address:', DIAMOND)

    const iface = getIsbeFactoryInterface()

    const facetArtifact = await artifacts.readArtifact('HashTimestampFacet')
    const facetBytecode = facetArtifact.bytecode
    console.log('\nHashTimestampFacet bytecode loaded:', facetBytecode.length / 2 - 1, 'bytes')

    // Step 1: Register business logic
    console.log('\n[1/3] Registering HashTimestampFacet as business logic...')
    console.log('   Resolver key:', HASH_TIMESTAMP_RESOLVER_KEY)
    const { businessAddress, version: blVersion } = await deployBusinessLogic(
        HASH_TIMESTAMP_RESOLVER_KEY, facetBytecode, DIAMOND, signer, iface
    )
    console.log('   Business logic registered')
    console.log('   Implementation:', businessAddress)
    console.log('   Version:', blVersion)

    // Step 2: Set configuration
    console.log('\n[2/3] Setting use case configuration...')
    console.log('   Config ID:', HASH_TIMESTAMP_CONFIG_ID)
    const { version: configVersion } = await setConfig(
        HASH_TIMESTAMP_CONFIG_ID, HASH_TIMESTAMP_RESOLVER_KEY, DIAMOND, signer, iface
    )
    console.log('   Configuration set, version:', configVersion)

    // Step 3: Deploy proxy
    console.log('\n[3/3] Deploying use case proxy...')
    const { proxy } = await deployUseCase(HASH_TIMESTAMP_CONFIG_ID, DIAMOND, signer, iface)
    console.log('   Use case proxy deployed')
    console.log('   Proxy address:', proxy)

    // Summary
    console.log('\nDeployment complete!')
    console.log('-------------------------------------------------------------')
    console.log('  Diamond (governance):  ', DIAMOND)
    console.log('  Resolver key:          ', HASH_TIMESTAMP_RESOLVER_KEY)
    console.log('  Config ID:             ', HASH_TIMESTAMP_CONFIG_ID)
    console.log('  Implementation:        ', businessAddress)
    console.log('  HashTimestamp proxy:   ', proxy)
    console.log('-------------------------------------------------------------')
}

main().catch((error: unknown) => {
    console.error(error)
    process.exit(1)
})
