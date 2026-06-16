import { expect } from 'chai'
import { ethers } from 'hardhat'
import { time } from '@nomicfoundation/hardhat-network-helpers'
import type {
    ProjectTestable,
    AlwaysValidSignatureVerifier,
    AlwaysInvalidSignatureVerifier,
    RevertingSignatureVerifier,
} from '../typechain-types'

// ---------------------------------------------------------------------------
// Constants matching contracts/constants/constants.sol
// ---------------------------------------------------------------------------

const DEFAULT_ADMIN_ROLE =
    '0x0000000000000000000000000000000000000000000000000000000000000000'

const SCHEMA_MANAGER_ROLE = ethers.id(
    'isbe.customers.ctb.role.audit-service.schema-manager'
)
const ALGORITHM_MANAGER_ROLE = ethers.id(
    'isbe.customers.ctb.role.audit-service.algorithm-manager'
)
const KEY_MANAGER_ROLE = ethers.id(
    'isbe.customers.ctb.role.audit-service.key-manager'
)
const KEY_REVOKER_ROLE = ethers.id(
    'isbe.customers.ctb.role.audit-service.key-revoker'
)
const ANCHOR_ROLE = ethers.id('isbe.customers.ctb.role.audit-service.anchor')

const SCHEMA_ID = ethers.id('schema.audit.v1')
const SCHEMA_VERSION = ethers.id('1.0.0')
const SCHEMA_HASH = ethers.id('schema-body-hash')
const EIP712_TYPE_HASH = ethers.keccak256(
    ethers.toUtf8Bytes(
        'AuditEnvelope(bytes32 eventHash,bytes32 schemaId,bytes32 schemaVersion,bytes32 schemaHash,bytes32 eip712TypeHash,bytes32 tenantId,uint8 status,bytes32 nonce)'
    )
)

const ALGO_ALWAYS_OK = ethers.id('algo.always-ok')
const ALGO_ALWAYS_BAD = ethers.id('algo.always-bad')
const ALGO_REVERTING = ethers.id('algo.reverting')

const TENANT_A = ethers.id('tenant.A')
const TENANT_B = ethers.id('tenant.B')

const KEY_A1 = ethers.id('key.A.1')
const KEY_A2 = ethers.id('key.A.2')
const KEY_B1 = ethers.id('key.B.1')
const KEY_A_BAD = ethers.id('key.A.bad')
const KEY_A_REVERT = ethers.id('key.A.revert')

const SAMPLE_PUBKEY = '0x04' + 'aa'.repeat(64)
const SAMPLE_SIG = '0x' + 'bb'.repeat(65)

const ZERO_BYTES32 =
    '0x0000000000000000000000000000000000000000000000000000000000000000'

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

interface Fixture {
    project: ProjectTestable
    validVerifier: AlwaysValidSignatureVerifier
    invalidVerifier: AlwaysInvalidSignatureVerifier
    revertingVerifier: RevertingSignatureVerifier
    admin: Awaited<ReturnType<typeof ethers.getSigner>>
    operator: Awaited<ReturnType<typeof ethers.getSigner>>
    stranger: Awaited<ReturnType<typeof ethers.getSigner>>
}

async function deployFixture(): Promise<Fixture> {
    const [admin, operator, stranger] = await ethers.getSigners()

    const ProjectTestable = await ethers.getContractFactory('ProjectTestable')
    const project = (await ProjectTestable.deploy()) as unknown as ProjectTestable
    await project.waitForDeployment()
    await (await project.initializeForTest(admin.address, operator.address)).wait()

    const ValidFactory = await ethers.getContractFactory(
        'AlwaysValidSignatureVerifier'
    )
    const validVerifier =
        (await ValidFactory.deploy()) as unknown as AlwaysValidSignatureVerifier
    await validVerifier.waitForDeployment()

    const InvalidFactory = await ethers.getContractFactory(
        'AlwaysInvalidSignatureVerifier'
    )
    const invalidVerifier =
        (await InvalidFactory.deploy()) as unknown as AlwaysInvalidSignatureVerifier
    await invalidVerifier.waitForDeployment()

    const RevertingFactory = await ethers.getContractFactory(
        'RevertingSignatureVerifier'
    )
    const revertingVerifier =
        (await RevertingFactory.deploy()) as unknown as RevertingSignatureVerifier
    await revertingVerifier.waitForDeployment()

    return {
        project,
        validVerifier,
        invalidVerifier,
        revertingVerifier,
        admin,
        operator,
        stranger,
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

interface Envelope {
    eventHash: string
    schemaId: string
    schemaVersion: string
    schemaHash: string
    eip712TypeHash: string
    tenantId: string
    status: number
    nonce: string
}

function makeEnvelope(overrides: Partial<Envelope> = {}): Envelope {
    return {
        eventHash: overrides.eventHash ?? ethers.id('event.1'),
        schemaId: overrides.schemaId ?? SCHEMA_ID,
        schemaVersion: overrides.schemaVersion ?? SCHEMA_VERSION,
        schemaHash: overrides.schemaHash ?? SCHEMA_HASH,
        eip712TypeHash: overrides.eip712TypeHash ?? EIP712_TYPE_HASH,
        tenantId: overrides.tenantId ?? TENANT_A,
        status: overrides.status ?? 1,
        nonce: overrides.nonce ?? ethers.id('nonce.1'),
    }
}

async function bootstrapHappyPath(
    f: Fixture,
    opts: {
        expiresAt?: bigint
        registerInvalidAlgo?: boolean
        registerRevertingAlgo?: boolean
    } = {}
) {
    const op = f.project.connect(f.operator)
    await op.registerSchema(SCHEMA_ID, SCHEMA_VERSION, SCHEMA_HASH, EIP712_TYPE_HASH)
    await op.registerAlgorithm(
        ALGO_ALWAYS_OK,
        await f.validVerifier.getAddress()
    )
    if (opts.registerInvalidAlgo) {
        await op.registerAlgorithm(
            ALGO_ALWAYS_BAD,
            await f.invalidVerifier.getAddress()
        )
    }
    if (opts.registerRevertingAlgo) {
        await op.registerAlgorithm(
            ALGO_REVERTING,
            await f.revertingVerifier.getAddress()
        )
    }
    const expires = opts.expiresAt ?? 0n
    await op.registerKey(KEY_A1, ALGO_ALWAYS_OK, SAMPLE_PUBKEY, TENANT_A, expires)
    await op.registerKey(KEY_A2, ALGO_ALWAYS_OK, SAMPLE_PUBKEY, TENANT_A, expires)
    await op.registerKey(KEY_B1, ALGO_ALWAYS_OK, SAMPLE_PUBKEY, TENANT_B, expires)
}

function withSig(keyId: string, sig: string = SAMPLE_SIG) {
    return { keyId, signature: sig }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('Project (CTB Audit Service V1)', () => {
    describe('Key lifecycle (Milestone 1 — timestamp-based activeness)', () => {
        it('reports active after register', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)

            expect(await f.project.isKeyActive(KEY_A1)).to.equal(true)

            const now = BigInt(await time.latest())
            expect(await f.project.isKeyActiveAt(KEY_A1, now)).to.equal(true)
        })

        it('returns true for a timestamp BEFORE revocation, false at/after', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)

            const tsBeforeRevoke = BigInt(await time.latest())

            // Advance the clock so the revocation timestamp is strictly after
            // the registration timestamp we captured.
            await time.increase(60)
            const revokeTx = await f.project.connect(f.operator).revokeKey(KEY_A1)
            await revokeTx.wait()
            const revokedAt = BigInt(await time.latest())

            // Audit a historical timestamp before revocation: must remain active.
            expect(
                await f.project.isKeyActiveAt(KEY_A1, tsBeforeRevoke)
            ).to.equal(true)

            // Current time (= revokedAt): not active anymore.
            expect(
                await f.project.isKeyActiveAt(KEY_A1, revokedAt)
            ).to.equal(false)
            // And a moment after: still not active.
            expect(
                await f.project.isKeyActiveAt(KEY_A1, revokedAt + 100n)
            ).to.equal(false)
            expect(await f.project.isKeyActive(KEY_A1)).to.equal(false)
        })

        it('honors expiresAt: active before, inactive at and after', async () => {
            const f = await deployFixture()
            const now = BigInt(await time.latest())
            const expiresAt = now + 1000n
            await bootstrapHappyPath(f, { expiresAt })

            expect(await f.project.isKeyActiveAt(KEY_A1, expiresAt - 1n)).to.equal(
                true
            )
            expect(await f.project.isKeyActiveAt(KEY_A1, expiresAt)).to.equal(false)
            expect(await f.project.isKeyActiveAt(KEY_A1, expiresAt + 1n)).to.equal(
                false
            )
        })

        it('rejects expiresAt not strictly in the future', async () => {
            const f = await deployFixture()
            const op = f.project.connect(f.operator)
            await op.registerSchema(
                SCHEMA_ID,
                SCHEMA_VERSION,
                SCHEMA_HASH,
                EIP712_TYPE_HASH
            )
            await op.registerAlgorithm(
                ALGO_ALWAYS_OK,
                await f.validVerifier.getAddress()
            )
            const past = BigInt(await time.latest())
            await expect(
                op.registerKey(KEY_A1, ALGO_ALWAYS_OK, SAMPLE_PUBKEY, TENANT_A, past)
            ).to.be.revertedWithCustomError(f.project, 'InvalidExpiresAt')
        })

        it('revoking an already-inactive key reverts KeyNotActive', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            await f.project.connect(f.operator).revokeKey(KEY_A1)
            await expect(
                f.project.connect(f.operator).revokeKey(KEY_A1)
            ).to.be.revertedWithCustomError(f.project, 'KeyNotActive')
        })

        it('revoking a non-existent key reverts KeyNotRegistered', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            await expect(
                f.project.connect(f.operator).revokeKey(ethers.id('nope'))
            ).to.be.revertedWithCustomError(f.project, 'KeyNotRegistered')
        })
    })

    describe('Signer storage (Milestone 2 — O(1) signer lookup via signerIndexPlusOne)', () => {
        it('anchors with multiple signers and exposes them by keyId', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)

            const envelope = makeEnvelope()
            const tx = await f.project
                .connect(f.operator)
                .anchor(envelope, [withSig(KEY_A1, '0x' + '11'.repeat(65)), withSig(KEY_A2, '0x' + '22'.repeat(65))])
            await tx.wait()

            expect(await f.project.getSignerCount(envelope.eventHash)).to.equal(2n)
            const signers = await f.project.getSigners(envelope.eventHash)
            expect(signers).to.have.lengthOf(2)

            expect(await f.project.hasSigner(envelope.eventHash, KEY_A1)).to.equal(
                true
            )
            expect(await f.project.hasSigner(envelope.eventHash, KEY_A2)).to.equal(
                true
            )
            expect(await f.project.hasSigner(envelope.eventHash, KEY_B1)).to.equal(
                false
            )

            const s1 = await f.project.getSigner(envelope.eventHash, KEY_A1)
            const s2 = await f.project.getSigner(envelope.eventHash, KEY_A2)
            expect(s1.keyId).to.equal(KEY_A1)
            expect(s2.keyId).to.equal(KEY_A2)
            // Commitments are over the raw signature bytes per signer.
            expect(s1.signatureCommitment).to.equal(
                ethers.keccak256('0x' + '11'.repeat(65))
            )
            expect(s2.signatureCommitment).to.equal(
                ethers.keccak256('0x' + '22'.repeat(65))
            )
        })

        it('getSigner reverts SignerNotFound for absent (eventHash, keyId)', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope()
            await f.project
                .connect(f.operator)
                .anchor(envelope, [withSig(KEY_A1)])
            await expect(
                f.project.getSigner(envelope.eventHash, KEY_A2)
            ).to.be.revertedWithCustomError(f.project, 'SignerNotFound')
        })

        it('repeated keyId in the same anchor batch reverts DuplicateSigner', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope()
            await expect(
                f.project
                    .connect(f.operator)
                    .anchor(envelope, [withSig(KEY_A1), withSig(KEY_A1)])
            ).to.be.revertedWithCustomError(f.project, 'DuplicateSigner')
        })
    })

    describe('Cross-tenant isolation', () => {
        it('a key from tenant A signing a tenant B envelope reverts KeyTenantMismatch', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope({ tenantId: TENANT_B })
            await expect(
                f.project.connect(f.operator).anchor(envelope, [withSig(KEY_A1)])
            ).to.be.revertedWithCustomError(f.project, 'KeyTenantMismatch')
        })
    })

    describe('Idempotency', () => {
        it('re-anchoring the same eventHash reverts EventAlreadyAnchored', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope()
            await f.project
                .connect(f.operator)
                .anchor(envelope, [withSig(KEY_A1)])
            await expect(
                f.project.connect(f.operator).anchor(envelope, [withSig(KEY_A2)])
            ).to.be.revertedWithCustomError(f.project, 'EventAlreadyAnchored')
        })
    })

    describe('Schema and algorithm guards', () => {
        it('disabled schema reverts SchemaDisabled', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            await f.project
                .connect(f.operator)
                .setSchemaEnabled(SCHEMA_ID, SCHEMA_VERSION, false)
            const envelope = makeEnvelope()
            await expect(
                f.project.connect(f.operator).anchor(envelope, [withSig(KEY_A1)])
            ).to.be.revertedWithCustomError(f.project, 'SchemaDisabled')
        })

        it('schemaHash mismatch reverts SchemaHashMismatch', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope({ schemaHash: ethers.id('other') })
            await expect(
                f.project.connect(f.operator).anchor(envelope, [withSig(KEY_A1)])
            ).to.be.revertedWithCustomError(f.project, 'SchemaHashMismatch')
        })

        it('eip712TypeHash mismatch reverts Eip712TypeHashMismatch', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope({ eip712TypeHash: ethers.id('other') })
            await expect(
                f.project.connect(f.operator).anchor(envelope, [withSig(KEY_A1)])
            ).to.be.revertedWithCustomError(f.project, 'Eip712TypeHashMismatch')
        })

        it('disabled algorithm reverts AlgorithmDisabled', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            await f.project
                .connect(f.operator)
                .setAlgorithmEnabled(ALGO_ALWAYS_OK, false)
            const envelope = makeEnvelope()
            await expect(
                f.project.connect(f.operator).anchor(envelope, [withSig(KEY_A1)])
            ).to.be.revertedWithCustomError(f.project, 'AlgorithmDisabled')
        })

        it('unregistered key reverts KeyNotRegistered', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope()
            await expect(
                f.project
                    .connect(f.operator)
                    .anchor(envelope, [withSig(ethers.id('unknown'))])
            ).to.be.revertedWithCustomError(f.project, 'KeyNotRegistered')
        })

        it('registering a key against an unregistered algorithm reverts AlgorithmNotRegistered', async () => {
            const f = await deployFixture()
            const op = f.project.connect(f.operator)
            await op.registerSchema(
                SCHEMA_ID,
                SCHEMA_VERSION,
                SCHEMA_HASH,
                EIP712_TYPE_HASH
            )
            await expect(
                op.registerKey(
                    KEY_A1,
                    ethers.id('algo.unknown'),
                    SAMPLE_PUBKEY,
                    TENANT_A,
                    0n
                )
            ).to.be.revertedWithCustomError(f.project, 'AlgorithmNotRegistered')
        })

        it('registering an algorithm with address zero reverts InvalidVerifierAddress', async () => {
            const f = await deployFixture()
            const op = f.project.connect(f.operator)

            await expect(
                op.registerAlgorithm(ALGO_ALWAYS_OK, ethers.ZeroAddress)
            ).to.be.revertedWithCustomError(f.project, 'InvalidVerifierAddress')
        })

        it('registering an algorithm with an EOA verifier reverts InvalidVerifierAddress', async () => {
            const f = await deployFixture()
            const op = f.project.connect(f.operator)

            await expect(
                op.registerAlgorithm(ALGO_ALWAYS_OK, f.stranger.address)
            ).to.be.revertedWithCustomError(f.project, 'InvalidVerifierAddress')
        })

        it('registering a key against a disabled algorithm reverts AlgorithmDisabled', async () => {
            const f = await deployFixture()
            const op = f.project.connect(f.operator)
            await op.registerAlgorithm(
                ALGO_ALWAYS_OK,
                await f.validVerifier.getAddress()
            )
            await op.setAlgorithmEnabled(ALGO_ALWAYS_OK, false)
            await expect(
                op.registerKey(
                    KEY_A1,
                    ALGO_ALWAYS_OK,
                    SAMPLE_PUBKEY,
                    TENANT_A,
                    0n
                )
            ).to.be.revertedWithCustomError(f.project, 'AlgorithmDisabled')
        })

        it('registering a duplicate schema reverts SchemaAlreadyRegistered', async () => {
            const f = await deployFixture()
            const op = f.project.connect(f.operator)
            await op.registerSchema(
                SCHEMA_ID,
                SCHEMA_VERSION,
                SCHEMA_HASH,
                EIP712_TYPE_HASH
            )
            await expect(
                op.registerSchema(
                    SCHEMA_ID,
                    SCHEMA_VERSION,
                    SCHEMA_HASH,
                    EIP712_TYPE_HASH
                )
            ).to.be.revertedWithCustomError(f.project, 'SchemaAlreadyRegistered')
        })

        it('registering a duplicate algorithm reverts AlgorithmAlreadyRegistered', async () => {
            const f = await deployFixture()
            const op = f.project.connect(f.operator)
            await op.registerAlgorithm(
                ALGO_ALWAYS_OK,
                await f.validVerifier.getAddress()
            )
            await expect(
                op.registerAlgorithm(
                    ALGO_ALWAYS_OK,
                    await f.validVerifier.getAddress()
                )
            ).to.be.revertedWithCustomError(f.project, 'AlgorithmAlreadyRegistered')
        })
    })

    describe('Envelope validation', () => {
        it('zero eventHash reverts InvalidEventHash', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope({ eventHash: ZERO_BYTES32 })
            await expect(
                f.project.connect(f.operator).anchor(envelope, [withSig(KEY_A1)])
            ).to.be.revertedWithCustomError(f.project, 'InvalidEventHash')
        })

        it('zero nonce reverts InvalidNonce', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope({ nonce: ZERO_BYTES32 })
            await expect(
                f.project.connect(f.operator).anchor(envelope, [withSig(KEY_A1)])
            ).to.be.revertedWithCustomError(f.project, 'InvalidNonce')
        })

        it('zero schemaHash reverts InvalidSchemaHash', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope({ schemaHash: ZERO_BYTES32 })
            await expect(
                f.project.connect(f.operator).anchor(envelope, [withSig(KEY_A1)])
            ).to.be.revertedWithCustomError(f.project, 'InvalidSchemaHash')
        })

        it('zero eip712TypeHash reverts InvalidEip712TypeHash', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope({ eip712TypeHash: ZERO_BYTES32 })
            await expect(
                f.project.connect(f.operator).anchor(envelope, [withSig(KEY_A1)])
            ).to.be.revertedWithCustomError(f.project, 'InvalidEip712TypeHash')
        })

        it('zero tenantId reverts InvalidTenantId', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope({ tenantId: ZERO_BYTES32 })
            await expect(
                f.project.connect(f.operator).anchor(envelope, [withSig(KEY_A1)])
            ).to.be.revertedWithCustomError(f.project, 'InvalidTenantId')
        })

        it('empty signatures array reverts NoSignaturesProvided', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope()
            await expect(
                f.project.connect(f.operator).anchor(envelope, [])
            ).to.be.revertedWithCustomError(f.project, 'NoSignaturesProvided')
        })

        it('verifySignature returns false for malformed envelope (no revert)', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            for (const malformed of [
                makeEnvelope({ schemaHash: ZERO_BYTES32 }),
                makeEnvelope({ eip712TypeHash: ZERO_BYTES32 }),
                makeEnvelope({ eventHash: ZERO_BYTES32 }),
                makeEnvelope({ nonce: ZERO_BYTES32 }),
            ]) {
                expect(
                    await f.project.verifySignature(malformed, withSig(KEY_A1))
                ).to.equal(false)
            }
        })
    })

    describe('EIP-712 binding', () => {
        it('hashEnvelope is stable and matches off-chain TypedDataEncoder', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope()
            const d1 = await f.project.hashEnvelope(envelope)
            const d2 = await f.project.hashEnvelope(envelope)
            expect(d1).to.equal(d2)

            const net = await ethers.provider.getNetwork()
            const domain = {
                name: 'CTB Audit Service',
                version: '1',
                chainId: Number(net.chainId),
                verifyingContract: await f.project.getAddress(),
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
            const offchain = ethers.TypedDataEncoder.hash(domain, types, envelope)
            expect(d1).to.equal(offchain)
        })

        it('digest changes when verifyingContract changes', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)

            const ProjectTestableFactory = await ethers.getContractFactory(
                'ProjectTestable'
            )
            const other =
                (await ProjectTestableFactory.deploy()) as unknown as ProjectTestable
            await other.waitForDeployment()
            await (
                await other.initializeForTest(f.admin.address, f.operator.address)
            ).wait()
            await (
                await other
                    .connect(f.operator)
                    .registerSchema(
                        SCHEMA_ID,
                        SCHEMA_VERSION,
                        SCHEMA_HASH,
                        EIP712_TYPE_HASH
                    )
            ).wait()

            const envelope = makeEnvelope()
            const d1 = await f.project.hashEnvelope(envelope)
            const d2 = await other.hashEnvelope(envelope)
            expect(d1).to.not.equal(d2)
        })

        it('always-valid mock causes verifySignature to return true and anchor to succeed', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope()
            expect(
                await f.project.verifySignature(envelope, withSig(KEY_A1))
            ).to.equal(true)
            await expect(
                f.project.connect(f.operator).anchor(envelope, [withSig(KEY_A1)])
            ).to.emit(f.project, 'AuditAnchored')
        })

        it('always-invalid mock makes verifySignature return false and anchor revert InvalidSignature', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f, { registerInvalidAlgo: true })
            await f.project
                .connect(f.operator)
                .registerKey(
                    KEY_A_BAD,
                    ALGO_ALWAYS_BAD,
                    SAMPLE_PUBKEY,
                    TENANT_A,
                    0n
                )
            const envelope = makeEnvelope({ eventHash: ethers.id('event.bad') })

            expect(
                await f.project.verifySignature(envelope, withSig(KEY_A_BAD))
            ).to.equal(false)

            await expect(
                f.project
                    .connect(f.operator)
                    .anchor(envelope, [withSig(KEY_A_BAD)])
            ).to.be.revertedWithCustomError(f.project, 'InvalidSignature')

            expect(await f.project.exists(envelope.eventHash)).to.equal(false)
        })

        it('reverting mock makes verifySignature return false and anchor revert InvalidSignature', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f, { registerRevertingAlgo: true })
            await f.project
                .connect(f.operator)
                .registerKey(
                    KEY_A_REVERT,
                    ALGO_REVERTING,
                    SAMPLE_PUBKEY,
                    TENANT_A,
                    0n
                )
            const envelope = makeEnvelope({ eventHash: ethers.id('event.revert') })

            expect(
                await f.project.verifySignature(envelope, withSig(KEY_A_REVERT))
            ).to.equal(false)

            await expect(
                f.project
                    .connect(f.operator)
                    .anchor(envelope, [withSig(KEY_A_REVERT)])
            ).to.be.revertedWithCustomError(f.project, 'InvalidSignature')

            expect(await f.project.exists(envelope.eventHash)).to.equal(false)
        })

        it('verifySignatures returns per-signature booleans', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f, { registerInvalidAlgo: true })
            await f.project
                .connect(f.operator)
                .registerKey(
                    KEY_A_BAD,
                    ALGO_ALWAYS_BAD,
                    SAMPLE_PUBKEY,
                    TENANT_A,
                    0n
                )
            const envelope = makeEnvelope()
            const results = await f.project.verifySignatures(envelope, [
                withSig(KEY_A1),
                withSig(KEY_A_BAD),
            ])
            expect(results[0]).to.equal(true)
            expect(results[1]).to.equal(false)
        })
    })

    describe('Pausing', () => {
        it('whenNotPaused functions revert while paused', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            await f.project.pauseForTest()

            // anchor
            const envelope = makeEnvelope()
            await expect(
                f.project.connect(f.operator).anchor(envelope, [withSig(KEY_A1)])
            ).to.be.reverted

            // registerSchema
            await expect(
                f.project
                    .connect(f.operator)
                    .registerSchema(
                        ethers.id('schema.2'),
                        SCHEMA_VERSION,
                        SCHEMA_HASH,
                        EIP712_TYPE_HASH
                    )
            ).to.be.reverted

            // revokeKey
            await expect(
                f.project.connect(f.operator).revokeKey(KEY_A1)
            ).to.be.reverted
        })

        it('view functions stay callable while paused', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            await f.project.pauseForTest()
            // Views must not revert because of pause.
            expect(await f.project.isKeyActive(KEY_A1)).to.equal(true)
            expect(await f.project.exists(ethers.id('event.none'))).to.equal(false)
        })
    })

    describe('RBAC', () => {
        it('registerSchema requires SCHEMA_MANAGER_ROLE', async () => {
            const f = await deployFixture()
            await expect(
                f.project
                    .connect(f.stranger)
                    .registerSchema(
                        SCHEMA_ID,
                        SCHEMA_VERSION,
                        SCHEMA_HASH,
                        EIP712_TYPE_HASH
                    )
            ).to.be.reverted
        })

        it('registerAlgorithm requires ALGORITHM_MANAGER_ROLE', async () => {
            const f = await deployFixture()
            await expect(
                f.project
                    .connect(f.stranger)
                    .registerAlgorithm(
                        ALGO_ALWAYS_OK,
                        await f.validVerifier.getAddress()
                    )
            ).to.be.reverted
        })

        it('registerKey requires KEY_MANAGER_ROLE', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            await expect(
                f.project
                    .connect(f.stranger)
                    .registerKey(
                        ethers.id('key.x'),
                        ALGO_ALWAYS_OK,
                        SAMPLE_PUBKEY,
                        TENANT_A,
                        0n
                    )
            ).to.be.reverted
        })

        it('revokeKey requires KEY_REVOKER_ROLE', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            await expect(
                f.project.connect(f.stranger).revokeKey(KEY_A1)
            ).to.be.reverted
        })

        it('anchor requires ANCHOR_ROLE', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope()
            await expect(
                f.project.connect(f.stranger).anchor(envelope, [withSig(KEY_A1)])
            ).to.be.reverted
        })

        it('setSchemaEnabled / setAlgorithmEnabled require manager roles', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            await expect(
                f.project
                    .connect(f.stranger)
                    .setSchemaEnabled(SCHEMA_ID, SCHEMA_VERSION, false)
            ).to.be.reverted
            await expect(
                f.project
                    .connect(f.stranger)
                    .setAlgorithmEnabled(ALGO_ALWAYS_OK, false)
            ).to.be.reverted
        })
    })

    describe('Metadata', () => {
        it('version() returns the EIP-712 domain version constant', async () => {
            const f = await deployFixture()
            expect(await f.project.version()).to.equal('1')
        })

        it('eip712Domain returns name, version and verifyingContract', async () => {
            const f = await deployFixture()
            // Solidity override of eip712Domain renames the `version` return
            // to `version_` to avoid shadowing the `version()` function; the
            // ABI reflects that name.
            const [, name, version_, , verifyingContract] =
                await f.project.eip712Domain()
            expect(name).to.equal('CTB Audit Service')
            expect(version_).to.equal('1')
            expect(verifyingContract).to.equal(await f.project.getAddress())
        })
    })
})
