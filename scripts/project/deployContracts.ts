import { ethers, artifacts } from 'hardhat'
import { Interface, Signer, TransactionReceipt, Contract } from 'ethers'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs'
import path from 'path'

// --- Constants ---------------------------------------------------------------

/** ISBE Diamond proxy (genesis) - EIP-2535 governance entry point */
const DIAMOND = '0x00000000000000000000000000000000000015BE'
const DEFAULT_ADMIN_ROLE =
    '0x0000000000000000000000000000000000000000000000000000000000000000'

const PLATFORM_ROLES = {
    BUSINESS_LOGIC_DEPLOYER: '0xdc99c621188983b30fd7ff7b62ee13c081548c6b000e3c54b59686f091418069',
    GOVERNANCE_CONFIGURATION_MANAGER: '0xc4fca0e2ae1ffe7494d7a1a0ee458ac6b6d84e022ad4f87c1742be5599e5e7fb',
    PROXY_DEPLOYER: '0xc6832bf28cac8042fe5597e3b605a7fa9af230954df24409efd82699171f3c26',
}

const GOVERNANCE_FACETS = [
    {
        name: 'IsbeLoupeFacet',
        key: '0x360faa2d547f0a951a5b1da060a4ffb56888bf8ad05db9de4d6d09b3eae1e5e2',
        path: '@red-isbe/isbe-contracts/artifacts/contracts/proxies/isbeproxy/facets/IsbeLoupeFacet.sol/IsbeLoupeFacet.json'
    },
    {
        name: 'IsbeCutFacet',
        key: '0x3e325d62f8652528edf5d41ed730a283b473d9e55ee9b6631b261b52199eac25',
        path: '@red-isbe/isbe-contracts/artifacts/contracts/proxies/isbeproxy/facets/IsbeCutFacet.sol/IsbeCutFacet.json'
    },
    {
        name: 'ISBEPauseFacet',
        key: '0x7fabf0f3ed655fa26f86c82ae5da60e0ade03a5d35a9ff2985709278942966d3',
        path: '@red-isbe/isbe-contracts/artifacts/contracts/pause/ISBEPauseFacet.sol/ISBEPauseFacet.json'
    },
    {
        name: 'AccessControlFacet',
        key: '0xa4de16c45770db08a06a2cdfeb0229e16d2ff660f7f1bf74c3dc07212770c70c',
        path: '@red-isbe/isbe-contracts/artifacts/contracts/access/accessControl/AccessControlFacet.sol/AccessControlFacet.json'
    },
    {
        name: 'AccessControlDidFacet',
        key: '0x91be68699977a17d16f4f996441c2bbd87a413d1114ef61d6d70019fc7904f4a',
        path: '@red-isbe/isbe-contracts/artifacts/contracts/access/accessControl/AccessControlDidFacet.sol/AccessControlDidFacet.json'
    }
]

const PROJECT_ROLE = ethers.id('isbe.customers.ctb.role.audit-service.manager')
const PROJECT_SCHEMA_MANAGER_ROLE = ethers.id('isbe.customers.ctb.role.audit-service.schema-manager')
const PROJECT_ALGORITHM_MANAGER_ROLE = ethers.id('isbe.customers.ctb.role.audit-service.algorithm-manager')
const PROJECT_KEY_MANAGER_ROLE = ethers.id('isbe.customers.ctb.role.audit-service.key-manager')
const PROJECT_KEY_REVOKER_ROLE = ethers.id('isbe.customers.ctb.role.audit-service.key-revoker')
const PROJECT_ANCHOR_ROLE = ethers.id('isbe.customers.ctb.role.audit-service.anchor')

const PROJECT_RESOLVER_KEY_STRING = 'isbe.customers.ctb.audit-service.v1.resolver.key'
const PROJECT_CONFIG_ID_STRING = 'isbe.customers.ctb.audit-service.v1.configuration'
const PROJECT_RESOLVER_KEY = ethers.id(PROJECT_RESOLVER_KEY_STRING)
const PROJECT_CONFIG_ID = ethers.id(PROJECT_CONFIG_ID_STRING)

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
    throw new Error(
        `Event '${eventName}' not found in receipt (block ${receipt.blockNumber})`
    )
}

// --- Deployment stages -------------------------------------------------------

async function ensureRoles(signer: Signer) {
    console.log('[..] Checking platform roles...')
    const signerAddress = await signer.getAddress()
    const abi = ['function hasRole(bytes32 role, address account) view returns (bool)', 'function grantRole(bytes32 role, address account)']
    const access = new Contract(DIAMOND, abi, signer)

    for (const [name, role] of Object.entries(PLATFORM_ROLES)) {
        const has = await access.hasRole(role, signerAddress)
        if (!has) {
            console.log(`[..] Granting ${name}...`)
            await (await access.grantRole(role, signerAddress)).wait()
        }
    }
    console.log('[OK] Platform roles confirmed')
}

async function ensurePlatformFacets(signer: Signer, factory: Contract, iface: Interface) {
    console.log('[..] Checking platform governance facets...')
    for (const facet of GOVERNANCE_FACETS) {
        const addr = await factory.getBusinessLogicAddress(facet.key, 0)
        if (addr === ethers.ZeroAddress) {
            console.log(`[..] Registering missing facet: ${facet.name}...`)
            const artifactPath = require.resolve(facet.path)
            const { bytecode } = JSON.parse(readFileSync(artifactPath, 'utf8'))
            const data = iface.encodeFunctionData('deploy', [facet.key, bytecode])
            await (await signer.sendTransaction({ to: DIAMOND, data, gasLimit: 15_000_000 })).wait()
            console.log(`[OK] ${facet.name} registered`)
        }
    }
    console.log('[OK] Platform governance facets confirmed')
}

async function deployProject(signer: Signer, factory: Contract, iface: Interface) {
    console.log('[..] Registering ProjectFacet...')
    const projectArtifact = await artifacts.readArtifact('ProjectFacet')
    const data = iface.encodeFunctionData('deploy', [PROJECT_RESOLVER_KEY, projectArtifact.bytecode])
    const tx = await signer.sendTransaction({ to: DIAMOND, data, gasLimit: 25_000_000 })
    const receipt = await tx.wait()
    const event = getEventFromReceipt('Deployed', receipt!, iface)
    console.log(`[OK] ProjectFacet version ${event.args.version} registered`)
    return event.args.version
}

async function configureUseCase(signer: Signer, blVersion: bigint, iface: Interface) {
    console.log('[..] Setting use case configuration...')
    const data = iface.encodeFunctionData('setConfiguration', [
        PROJECT_CONFIG_ID,
        [{ businessId: PROJECT_RESOLVER_KEY, version: blVersion }],
    ])
    const tx = await signer.sendTransaction({ to: DIAMOND, data, gasLimit: 25_000_000 })
    const receipt = await tx.wait()
    const event = getEventFromReceipt('ConfigurationSet', receipt!, iface)
    console.log(`[OK] Configuration set, version ${event.args.version}`)
    return event.args.version
}

async function deployProxy(signer: Signer, iface: Interface) {
    console.log('[..] Deploying use case proxy...')
    const signerAddress = await signer.getAddress()
    const rbacs = [
        [PROJECT_ROLE, [signerAddress]],
        [PROJECT_SCHEMA_MANAGER_ROLE, [signerAddress]],
        [PROJECT_ALGORITHM_MANAGER_ROLE, [signerAddress]],
        [PROJECT_KEY_MANAGER_ROLE, [signerAddress]],
        [PROJECT_KEY_REVOKER_ROLE, [signerAddress]],
        [PROJECT_ANCHOR_ROLE, [signerAddress]],
    ]
    const data = iface.encodeFunctionData('deployUseCase', [PROJECT_CONFIG_ID, 0, rbacs, false, [], []])
    const tx = await signer.sendTransaction({ to: DIAMOND, data, gasLimit: 25_000_000 })
    const receipt = await tx.wait()
    const event = getEventFromReceipt('UseCaseDeployed', receipt!, iface)
    console.log(`[OK] Use case proxy deployed at ${event.args.proxy}`)
    return event.args.proxy
}

async function writeLatestDeployment(
    proxy: string,
    implementation: string,
    businessVersion: bigint,
    configurationVersion: bigint,
    deployer: string
) {
    const deploymentsDir = path.join(process.cwd(), 'deployments')
    if (!existsSync(deploymentsDir)) {
        mkdirSync(deploymentsDir, { recursive: true })
    }

    const deployment = {
        network: 'isbe',
        chainId: (await ethers.provider.getNetwork()).chainId.toString(),
        diamond: DIAMOND,
        projectProxy: proxy,
        projectResolverKey: PROJECT_RESOLVER_KEY,
        projectConfigId: PROJECT_CONFIG_ID,
        implementation,
        businessVersion: businessVersion.toString(),
        configurationVersion: configurationVersion.toString(),
        deployer,
        timestamp: Math.floor(Date.now() / 1000),
    }

    const file = path.join(deploymentsDir, 'isbe-audit-latest.json')
    writeFileSync(file, `${JSON.stringify(deployment, null, 2)}\n`, 'utf8')
    console.log(`[OK] Deployment artifact written to ${path.relative(process.cwd(), file)}`)
}

// --- Main --------------------------------------------------------------------

async function main() {
    const [signer] = await ethers.getSigners()
    const iface = getIsbeFactoryInterface()
    const factory = new Contract(DIAMOND, iface, signer)

    console.log('--- Starting ISBE Audit Service Deployment ---')
    console.log('Account:', signer.address)
    console.log('Resolver key string:', PROJECT_RESOLVER_KEY_STRING)
    console.log('Config id string:', PROJECT_CONFIG_ID_STRING)
    
    await ensureRoles(signer)
    await ensurePlatformFacets(signer, factory, iface)
    const blVersion = await deployProject(signer, factory, iface)
    const implementation = await factory.getBusinessLogicAddress(PROJECT_RESOLVER_KEY, blVersion)
    const configurationVersion = await configureUseCase(signer, blVersion, iface)
    const proxy = await deployProxy(signer, iface)
    await writeLatestDeployment(proxy, implementation, blVersion, configurationVersion, signer.address)

    console.log('\nDeployment complete!')
    console.log('Proxy Address:', proxy)
    console.log('-----------------------------------------------')
}

main().catch((error) => {
    console.error(error)
    process.exit(1)
})
