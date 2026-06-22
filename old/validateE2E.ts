import { ethers } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { existsSync, readFileSync } from 'fs'
import path from 'path'

const DEPLOYMENT_FILE = path.join(
    process.cwd(),
    'deployments',
    'isbe-audit-latest.json'
)
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'
const ANCHOR_ROLE = ethers.id('isbe.customers.ctb.role.audit-service.anchor')

type ProxySource = 'env' | 'deployments/isbe-audit-latest.json'

type ProxyResolution = {
    projectProxy: string
    source: ProxySource
}

function resolveProjectProxy(): ProxyResolution {
    const envProxy = process.env.PROJECT_PROXY?.trim()
    if (envProxy) {
        return { projectProxy: envProxy, source: 'env' }
    }

    if (existsSync(DEPLOYMENT_FILE)) {
        const deployment = JSON.parse(readFileSync(DEPLOYMENT_FILE, 'utf8')) as {
            projectProxy?: string
        }
        if (deployment.projectProxy) {
            return {
                projectProxy: deployment.projectProxy,
                source: 'deployments/isbe-audit-latest.json',
            }
        }
    }

    throw new Error(
        'No Project proxy found. Run deployContracts.ts first or set PROJECT_PROXY.'
    )
}

function requirePrivateKey(): string {
    const privateKey = process.env.ACCOUNT_PRIVATE_KEY?.trim()
    if (!privateKey) {
        throw new Error('ACCOUNT_PRIVATE_KEY is required to produce raw ECDSA signatures.')
    }
    return privateKey
}

function rawSignature(privateKey: string, digest: string): string {
    const signingKey = new ethers.SigningKey(privateKey)
    const signature = signingKey.sign(digest)
    return ethers.Signature.from(signature).serialized
}

async function expectRevert(
    label: string,
    action: () => Promise<unknown>,
    expected?: string
) {
    try {
        await action()
    } catch (error: any) {
        const message = String(error?.message ?? error)
        if (!expected) {
            console.log(`[OK] ${label} reverted`)
            return
        }

        if (message.includes(expected)) {
            console.log(`[OK] ${label} reverted with ${expected}`)
            return
        }

        if (message.includes('Execution reverted') || message.includes('reverted')) {
            console.log(
                `[OK] ${label} reverted; node did not return a decoded ${expected} reason`
            )
            return
        }

        throw new Error(`${label} reverted, but not with ${expected}: ${message}`)
    }

    throw new Error(
        expected
            ? `${label} should have reverted with ${expected}`
            : `${label} should have reverted`
    )
}

async function assertProjectProxy(project: Contract) {
    try {
        const version = await project.version()
        if (version !== '1') {
            throw new Error(`Unexpected Project version '${version}', expected '1'.`)
        }
        console.log('[OK] Project version:', version)
    } catch (error: any) {
        throw new Error(
            `Project proxy does not look like a valid ProjectFacet/Audit Service proxy: ${
                error?.message ?? error
            }`
        )
    }
}

async function buildEnvelope(project: Contract, ids: any, label: string) {
    const eventHash = ethers.id(`ctb.audit.event.${label}.${ids.suffix}`)
    const envelope = {
        eventHash,
        schemaId: ids.schemaId,
        schemaVersion: ids.schemaVersion,
        schemaHash: ids.schemaHash,
        eip712TypeHash: ids.eip712TypeHash,
        tenantId: ids.tenantId,
        status: 1,
        nonce: ethers.id(`ctb.audit.nonce.${label}.${ids.suffix}`),
    }

    const onChainDigest = await project.hashEnvelope(envelope)
    const domain = {
        name: 'CTB Audit Service',
        version: '1',
        chainId: ids.chainId,
        verifyingContract: ids.projectProxy,
    }
    const types = {
        AuditEnvelope: [
            { name: 'eventHash', type: 'bytes32' },
            { name: 'schemaId', type: 'bytes32' },
            { name: 'schemaVersion', type: 'bytes32' },
            { name: 'schemaHash', type: 'bytes32' },
            { name: 'eip712TypeHash', type: 'bytes32' },
            { name: 'tenantId', type: 'bytes32' },
            { name: 'status', type: 'uint8' },
            { name: 'nonce', type: 'bytes32' },
        ],
    }
    const localDigest = ethers.TypedDataEncoder.hash(domain, types, envelope)
    if (onChainDigest !== localDigest) {
        throw new Error(
            `EIP-712 digest mismatch. on-chain=${onChainDigest} local=${localDigest}`
        )
    }

    return { envelope, digest: onChainDigest }
}

async function main() {
    const [signer] = await ethers.getSigners()
    const privateKey = requirePrivateKey()
    const { projectProxy, source } = resolveProjectProxy()
    const normalizedProxy = ethers.getAddress(projectProxy)
    const network = await ethers.provider.getNetwork()

    console.log('--- E2E VALIDATION START ---')
    console.log('Signer:', signer.address)
    console.log('ChainId:', network.chainId.toString())
    console.log('Project proxy:', normalizedProxy)
    console.log('Project proxy source:', source)

    if (normalizedProxy === ZERO_ADDRESS) {
        throw new Error('Project proxy cannot be address(0).')
    }

    const project = await ethers.getContractAt('IProject', normalizedProxy)
    await assertProjectProxy(project)

    console.log('\n[Step 1] Deploying EcdsaSecp256k1Verifier...')
    const VerifierFactory = await ethers.getContractFactory(
        'EcdsaSecp256k1Verifier'
    )
    const verifier = await VerifierFactory.deploy()
    await verifier.waitForDeployment()
    const verifierAddress = await verifier.getAddress()
    console.log('[OK] Verifier deployed at:', verifierAddress)

    const latestBlock = await ethers.provider.getBlock('latest')
    const suffix = `${network.chainId.toString()}-${latestBlock?.number ?? 0}-${
        latestBlock?.timestamp ?? 0
    }-${ethers.hexlify(ethers.randomBytes(8))}`
    const ids = {
        suffix,
        chainId: network.chainId,
        projectProxy: normalizedProxy,
        algorithmId: ethers.id(`ECDSA_SECP256K1_EIP712.${suffix}`),
        schemaId: ethers.id(`ISBE_AUDIT_V1.${suffix}`),
        schemaVersion: ethers.id(`1.0.0.${suffix}`),
        schemaHash: ethers.id(`SCHEMA_BODY_HASH.${suffix}`),
        eip712TypeHash: ethers.id(
            'AuditEnvelope(bytes32 eventHash,bytes32 schemaId,bytes32 schemaVersion,bytes32 schemaHash,bytes32 eip712TypeHash,bytes32 tenantId,uint8 status,bytes32 nonce)'
        ),
        tenantId: ethers.id(`did:isbe:ctb:tenant:${suffix}`),
        keyId: ethers.id(`ctb.audit.key.${suffix}`),
    }

    console.log('\n[Step 2] Configuring algorithm and schema...')
    await (await project.registerAlgorithm(ids.algorithmId, verifierAddress)).wait()
    console.log('[OK] Algorithm registered:', ids.algorithmId)
    await (
        await project.registerSchema(
            ids.schemaId,
            ids.schemaVersion,
            ids.schemaHash,
            ids.eip712TypeHash
        )
    ).wait()
    console.log('[OK] Schema registered:', ids.schemaId)

    console.log('\n[Step 3] Registering signer key...')
    const publicKey = ethers.AbiCoder.defaultAbiCoder().encode(
        ['address'],
        [signer.address]
    )
    await (
        await project.registerKey(
            ids.keyId,
            ids.algorithmId,
            publicKey,
            ids.tenantId,
            0
        )
    ).wait()
    console.log('[OK] Key registered:', ids.keyId)

    console.log('\n[Step 4] Signing and anchoring happy path...')
    const { envelope, digest } = await buildEnvelope(project, ids, 'happy')
    console.log('[OK] EIP-712 digest verified:', digest)
    const signatureInput = {
        keyId: ids.keyId,
        signature: rawSignature(privateKey, digest),
    }

    const anchorTx = await project.anchor(envelope, [signatureInput])
    await anchorTx.wait()
    console.log('[OK] Anchor transaction:', anchorTx.hash)

    console.log('\n[Step 5] Reading anchor and verifying signature...')
    const anchorInfo = await project.getAnchor(envelope.eventHash)
    const signers = await project.getSigners(envelope.eventHash)
    const signerCount = await project.getSignerCount(envelope.eventHash)
    const hasSigner = await project.hasSigner(envelope.eventHash, ids.keyId)
    const isValid = await project.verifySignature(envelope, signatureInput)

    if (anchorInfo.eventHash !== envelope.eventHash) {
        throw new Error('Stored anchor eventHash does not match envelope.')
    }
    if (signers.length !== 1 || signerCount !== 1n || !hasSigner || !isValid) {
        throw new Error('Anchor/signature readback validation failed.')
    }
    console.log('[OK] Anchor timestamp:', anchorInfo.anchoredAt.toString())
    console.log('[OK] Signers found:', signers.length)
    console.log('[OK] verifySignature returned true')

    console.log('\n[Step 6] Negative tests...')
    const unauthorised = Wallet.createRandom().connect(ethers.provider)
    await signer.sendTransaction({
        to: unauthorised.address,
        value: ethers.parseEther('0.01'),
    })
    const access = new Contract(
        normalizedProxy,
        ['function hasRole(bytes32 role, address account) view returns (bool)'],
        signer
    )
    const unauthorisedHasAnchorRole = await access.hasRole(
        ANCHOR_ROLE,
        unauthorised.address
    )
    if (unauthorisedHasAnchorRole) {
        throw new Error('Unexpected test setup: unauthorised account has anchor role.')
    }
    const unauthorisedProject = project.connect(unauthorised)
    const { envelope: unauthorisedEnvelope, digest: unauthorisedDigest } =
        await buildEnvelope(project, ids, 'unauthorised')
    const unauthorisedSignature = {
        keyId: ids.keyId,
        signature: rawSignature(privateKey, unauthorisedDigest),
    }
    await expectRevert(
        'account without anchor role',
        async () =>
            unauthorisedProject.anchor.staticCall(unauthorisedEnvelope, [
                unauthorisedSignature,
            ]),
        undefined
    )

    const wrongWallet = Wallet.createRandom()
    const wrongSignature = wrongWallet.signingKey.sign(digest)
    const wrongSignatureInput = {
        keyId: ids.keyId,
        signature: ethers.Signature.from(wrongSignature).serialized,
    }
    const invalidResult = await project.verifySignature(envelope, wrongSignatureInput)
    if (invalidResult !== false) {
        throw new Error('Invalid signature should have returned false.')
    }
    console.log('[OK] Invalid signature returned false')

    const { envelope: disabledEnvelope, digest: disabledDigest } =
        await buildEnvelope(project, ids, 'disabled-algorithm')
    const disabledSignature = {
        keyId: ids.keyId,
        signature: rawSignature(privateKey, disabledDigest),
    }
    await (await project.setAlgorithmEnabled(ids.algorithmId, false)).wait()
    const disabledAlgorithm = await project.getAlgorithm(ids.algorithmId)
    if (disabledAlgorithm.enabled) {
        throw new Error('Algorithm should be disabled before negative anchor test.')
    }
    await expectRevert(
        'disabled algorithm anchor',
        async () =>
            project.anchor.staticCall(disabledEnvelope, [disabledSignature]),
        'AlgorithmDisabled'
    )

    console.log('\n--- E2E VALIDATION COMPLETE ---')
}

main().catch((error) => {
    console.error(error)
    process.exit(1)
})
