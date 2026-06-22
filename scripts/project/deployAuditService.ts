import { ethers, artifacts } from 'hardhat'
import { Interface, Signer, TransactionReceipt } from 'ethers'
import { readFileSync } from 'fs'

// --- Constants ---------------------------------------------------------------

/** ISBE Diamond proxy (genesis) - EIP-2535 governance entry point */
const DIAMOND = '0x00000000000000000000000000000000000015BE'

/**
 * keccak256('isbe.customers.insurechain.auditService.resolver.key')
 * Value returned by AuditServiceFacet.businessIdIntrospection().
 *
 * node -e "const { ethers } = require('ethers'); console.log(ethers.keccak256(ethers.toUtf8Bytes('isbe.customers.insurechain.auditService.resolver.key')))"
 */
const AUDIT_SERVICE_RESOLVER_KEY =
    '0x' + ethers.id('isbe.customers.insurechain.auditService.resolver.key').slice(2)

/**
 * keccak256('isbe.customers.insurechain.auditService.config.id')
 * Defined in contracts/constants/constants.sol as _AUDIT_SERVICE_CONFIG_ID.
 *
 * node -e "const { ethers } = require('ethers'); console.log(ethers.keccak256(ethers.toUtf8Bytes('isbe.customers.insurechain.auditService.config.id')))"
 */
const AUDIT_SERVICE_CONFIG_ID =
    '0x' + ethers.id('isbe.customers.insurechain.auditService.config.id').slice(2)

const AUDIT_SERVICE_ROLE          = ethers.id('isbe.customers.insurechain.auditService.project.role')
const SCHEMA_MANAGER_ROLE         = ethers.id('isbe.customers.insurechain.auditService.project.role.schemaManager')
const ALGORITHM_MANAGER_ROLE      = ethers.id('isbe.customers.insurechain.auditService.project.role.algorithmManager')
const KEY_MANAGER_ROLE            = ethers.id('isbe.customers.insurechain.auditService.project.role.keyManager')
const KEY_REVOKER_ROLE            = ethers.id('isbe.customers.insurechain.auditService.project.role.keyRevoker')
const ANCHOR_ROLE                 = ethers.id('isbe.customers.insurechain.auditService.project.role.anchor')

// --- Helpers -----------------------------------------------------------------

function getIsbeFactoryInterface(): Interface {
    const abiPath = require.resolve(
        '@red-isbe/isbe-contracts/artifacts/contracts/factory/IIsbeFactory.sol/IIsbeFactory.json'
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
    throw new Error(`Event '${eventName}' not found in receipt (block ${receipt.blockNumber})`)
}

// --- Deployment steps --------------------------------------------------------

async function deployBusinessLogic(
    businessId: string,
    bytecode: string,
    signer: Signer,
    iface: Interface
): Promise<{ businessAddress: string; version: string }> {
    console.log('Sending deployBusinessLogic transaction...')
    const data = iface.encodeFunctionData('deploy', [businessId, bytecode])
    const tx = await signer.sendTransaction({ to: DIAMOND, data, gasLimit: 16_000_000 })
    console.log('   Transaction submitted:', tx.hash)
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
    signer: Signer,
    iface: Interface
): Promise<{ version: string }> {
    console.log('Sending setConfiguration transaction...')
    const data = iface.encodeFunctionData('setConfiguration', [
        configId,
        [{ businessId, version: 1 }],
    ])
    const tx = await signer.sendTransaction({ to: DIAMOND, data, gasLimit: 16_000_000 })
    console.log('   Transaction submitted:', tx.hash)
    const receipt = await tx.wait()
    if (!receipt || receipt.status !== 1)
        throw new Error('setConfiguration transaction failed or was reverted')
    const event = getEventFromReceipt('ConfigurationSet', receipt, iface)
    const { version } = event.args
    return { version: version.toString() }
}

async function deployUseCase(
    configId: string,
    signer: Signer,
    iface: Interface
): Promise<{ proxy: string }> {
    console.log('Sending deployUseCase transaction...')
    const signerAddress = await signer.getAddress()
    const rbacs = [
        [AUDIT_SERVICE_ROLE,     [signerAddress]],
        [SCHEMA_MANAGER_ROLE,    [signerAddress]],
        [ALGORITHM_MANAGER_ROLE, [signerAddress]],
        [KEY_MANAGER_ROLE,       [signerAddress]],
        [KEY_REVOKER_ROLE,       [signerAddress]],
        [ANCHOR_ROLE,            [signerAddress]],
    ]
    const data = iface.encodeFunctionData('deployUseCase', [
        configId,
        0,      // version (0 = latest)
        rbacs,
        false,  // initPause
        [],     // initBusinessIds
        [],     // initData
    ])
    const tx = await signer.sendTransaction({ to: DIAMOND, data, gasLimit: 16_000_000 })
    console.log('   Transaction submitted:', tx.hash)
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

    const facetArtifact = await artifacts.readArtifact('AuditServiceFacet')
    const facetBytecode = facetArtifact.bytecode
    console.log('\nAuditServiceFacet bytecode loaded:', facetBytecode.length / 2 - 1, 'bytes')

    // Step 1: Register business logic
    console.log('\n[1/3] Registering AuditServiceFacet as business logic...')
    console.log('   Resolver key:', AUDIT_SERVICE_RESOLVER_KEY)
    const { businessAddress, version: blVersion } = await deployBusinessLogic(
        AUDIT_SERVICE_RESOLVER_KEY, facetBytecode, signer, iface
    )
    console.log('   Implementation:', businessAddress)
    console.log('   Version:', blVersion)

    // Step 2: Set configuration
    console.log('\n[2/3] Setting use case configuration...')
    console.log('   Config ID:', AUDIT_SERVICE_CONFIG_ID)
    const { version: configVersion } = await setConfig(
        AUDIT_SERVICE_CONFIG_ID, AUDIT_SERVICE_RESOLVER_KEY, signer, iface
    )
    console.log('   Configuration set, version:', configVersion)

    // Step 3: Deploy proxy
    console.log('\n[3/3] Deploying use case proxy...')
    const { proxy } = await deployUseCase(AUDIT_SERVICE_CONFIG_ID, signer, iface)
    console.log('   Use case proxy deployed')
    console.log('   Proxy address:', proxy)

    // Summary
    console.log('\nDeployment complete!')
    console.log('-------------------------------------------------------------')
    console.log('  Diamond (governance):  ', DIAMOND)
    console.log('  Resolver key:          ', AUDIT_SERVICE_RESOLVER_KEY)
    console.log('  Config ID:             ', AUDIT_SERVICE_CONFIG_ID)
    console.log('  Implementation:        ', businessAddress)
    console.log('  AuditService proxy:    ', proxy)
    console.log('-------------------------------------------------------------')
}

main().catch((error: unknown) => {
    console.error(error)
    process.exit(1)
})
