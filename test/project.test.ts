import { expect } from 'chai'
import { ethers } from 'hardhat'
import { time } from '@nomicfoundation/hardhat-network-helpers'
import type { AuditServiceTestWrapper } from '../typechain-types'

// ---------------------------------------------------------------------------
// Constants matching contracts/constants/constants.sol
// ---------------------------------------------------------------------------

const SCHEMA_ID = ethers.id('schema.audit.v1')
const SCHEMA_VERSION = ethers.id('1.0.0')
const SCHEMA_HASH = ethers.id('schema-body-hash')
const EIP712_TYPE_HASH = ethers.keccak256(
    ethers.toUtf8Bytes(
        'AuditEnvelope(bytes32 eventHash,bytes32 schemaId,bytes32 schemaVersion,bytes32 schemaHash,bytes32 eip712TypeHash,bytes32 tenantId,uint8 status,bytes32 nonce)'
    )
)

const ECDSA_ALGORITHM_ID = ethers.id('ECDSA_SECP256K1_EIP712')
const UNSUPPORTED_ALGORITHM_ID = ethers.id('algo.unsupported')

const TENANT_A = ethers.id('tenant.A')
const TENANT_B = ethers.id('tenant.B')

const KEY_A1 = ethers.id('key.A.1')
const KEY_A2 = ethers.id('key.A.2')
const KEY_B1 = ethers.id('key.B.1')

const DUMMY_SIG = '0x' + 'bb'.repeat(65)
const MALFORMED_SIG = '0x1234'

const ZERO_BYTES32 =
    '0x0000000000000000000000000000000000000000000000000000000000000000'

const EIP712_DOMAIN_NAME = 'Insurechain Audit Service'
const EIP712_DOMAIN_VERSION = '1'

const AUDIT_ENVELOPE_TYPES = {
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

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

interface Fixture {
    project: AuditServiceTestWrapper
    admin: Awaited<ReturnType<typeof ethers.getSigner>>
    operator: Awaited<ReturnType<typeof ethers.getSigner>>
    stranger: Awaited<ReturnType<typeof ethers.getSigner>>
    signerA1: Awaited<ReturnType<typeof ethers.getSigner>>
    signerA2: Awaited<ReturnType<typeof ethers.getSigner>>
    signerB1: Awaited<ReturnType<typeof ethers.getSigner>>
    wrongSigner: Awaited<ReturnType<typeof ethers.getSigner>>
}

async function deployFixture(): Promise<Fixture> {
    const [
        admin,
        operator,
        stranger,
        signerA1,
        signerA2,
        signerB1,
        wrongSigner,
    ] = await ethers.getSigners()

    const AuditServiceTestWrapper = await ethers.getContractFactory(
        'AuditServiceTestWrapper'
    )
    const project =
        (await AuditServiceTestWrapper.deploy()) as unknown as AuditServiceTestWrapper
    await project.waitForDeployment()
    await (await project.initializeForTest(admin.address, operator.address)).wait()

    return {
        project,
        admin,
        operator,
        stranger,
        signerA1,
        signerA2,
        signerB1,
        wrongSigner,
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

function encodedSignerAddress(address: string): string {
    return ethers.AbiCoder.defaultAbiCoder().encode(['address'], [address])
}

function dummySig(keyId: string, sig: string = DUMMY_SIG) {
    return { keyId, signature: sig }
}

async function eip712Domain(project: AuditServiceTestWrapper) {
    const net = await ethers.provider.getNetwork()
    return {
        name: EIP712_DOMAIN_NAME,
        version: EIP712_DOMAIN_VERSION,
        chainId: net.chainId,
        verifyingContract: await project.getAddress(),
    }
}

function signerForKey(f: Fixture, keyId: string) {
    if (keyId === KEY_A1) return f.signerA1
    if (keyId === KEY_A2) return f.signerA2
    if (keyId === KEY_B1) return f.signerB1
    throw new Error(`No fixture signer mapped for keyId ${keyId}`)
}

async function signedSig(
    f: Fixture,
    keyId: string,
    envelope: Envelope,
    signer = signerForKey(f, keyId)
) {
    return {
        keyId,
        signature: await signer.signTypedData(
            await eip712Domain(f.project),
            AUDIT_ENVELOPE_TYPES,
            envelope
        ),
    }
}

async function bootstrapHappyPath(
    f: Fixture,
    opts: {
        expiresAt?: bigint
    } = {}
) {
    const op = f.project.connect(f.operator)
    await op.registerSchema(SCHEMA_ID, SCHEMA_VERSION, SCHEMA_HASH, EIP712_TYPE_HASH)
    await op.registerAlgorithm(ECDSA_ALGORITHM_ID)

    const expires = opts.expiresAt ?? 0n
    await op.registerKey(
        KEY_A1,
        ECDSA_ALGORITHM_ID,
        encodedSignerAddress(f.signerA1.address),
        TENANT_A,
        expires
    )
    await op.registerKey(
        KEY_A2,
        ECDSA_ALGORITHM_ID,
        encodedSignerAddress(f.signerA2.address),
        TENANT_A,
        expires
    )
    await op.registerKey(
        KEY_B1,
        ECDSA_ALGORITHM_ID,
        encodedSignerAddress(f.signerB1.address),
        TENANT_B,
        expires
    )
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('AuditService (unified ISBE Diamond facet)', () => {
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

            await time.increase(60)
            const revokeTx = await f.project.connect(f.operator).revokeKey(KEY_A1)
            await revokeTx.wait()
            const revokedAt = BigInt(await time.latest())

            expect(await f.project.isKeyActiveAt(KEY_A1, tsBeforeRevoke)).to.equal(
                true
            )
            expect(await f.project.isKeyActiveAt(KEY_A1, revokedAt)).to.equal(false)
            expect(await f.project.isKeyActiveAt(KEY_A1, revokedAt + 100n)).to.equal(
                false
            )
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
            await op.registerAlgorithm(ECDSA_ALGORITHM_ID)
            const past = BigInt(await time.latest())
            await expect(
                op.registerKey(
                    KEY_A1,
                    ECDSA_ALGORITHM_ID,
                    encodedSignerAddress(f.signerA1.address),
                    TENANT_A,
                    past
                )
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
            const sig1 = await signedSig(f, KEY_A1, envelope)
            const sig2 = await signedSig(f, KEY_A2, envelope)
            const tx = await f.project.connect(f.operator).anchor(envelope, [sig1, sig2])
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
            expect(s1.signatureCommitment).to.equal(ethers.keccak256(sig1.signature))
            expect(s2.signatureCommitment).to.equal(ethers.keccak256(sig2.signature))
        })

        it('getSigner reverts SignerNotFound for absent (eventHash, keyId)', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope()
            await f.project
                .connect(f.operator)
                .anchor(envelope, [await signedSig(f, KEY_A1, envelope)])
            await expect(
                f.project.getSigner(envelope.eventHash, KEY_A2)
            ).to.be.revertedWithCustomError(f.project, 'SignerNotFound')
        })

        it('repeated keyId in the same anchor batch reverts DuplicateSigner', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope()
            const sig = await signedSig(f, KEY_A1, envelope)
            await expect(
                f.project.connect(f.operator).anchor(envelope, [sig, sig])
            ).to.be.revertedWithCustomError(f.project, 'DuplicateSigner')
        })
    })

    describe('Cross-tenant isolation', () => {
        it('a key from tenant A signing a tenant B envelope reverts KeyTenantMismatch', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope({ tenantId: TENANT_B })
            await expect(
                f.project.connect(f.operator).anchor(envelope, [dummySig(KEY_A1)])
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
                .anchor(envelope, [await signedSig(f, KEY_A1, envelope)])
            await expect(
                f.project
                    .connect(f.operator)
                    .anchor(envelope, [await signedSig(f, KEY_A2, envelope)])
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
                f.project.connect(f.operator).anchor(envelope, [dummySig(KEY_A1)])
            ).to.be.revertedWithCustomError(f.project, 'SchemaDisabled')
        })

        it('schemaHash mismatch reverts SchemaHashMismatch', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope({ schemaHash: ethers.id('other') })
            await expect(
                f.project.connect(f.operator).anchor(envelope, [dummySig(KEY_A1)])
            ).to.be.revertedWithCustomError(f.project, 'SchemaHashMismatch')
        })

        it('eip712TypeHash mismatch reverts Eip712TypeHashMismatch', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope({ eip712TypeHash: ethers.id('other') })
            await expect(
                f.project.connect(f.operator).anchor(envelope, [dummySig(KEY_A1)])
            ).to.be.revertedWithCustomError(f.project, 'Eip712TypeHashMismatch')
        })

        it('disabled algorithm reverts AlgorithmDisabled', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            await f.project
                .connect(f.operator)
                .setAlgorithmEnabled(ECDSA_ALGORITHM_ID, false)
            const envelope = makeEnvelope()
            await expect(
                f.project.connect(f.operator).anchor(envelope, [dummySig(KEY_A1)])
            ).to.be.revertedWithCustomError(f.project, 'AlgorithmDisabled')
        })

        it('unregistered key reverts KeyNotRegistered', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope()
            await expect(
                f.project
                    .connect(f.operator)
                    .anchor(envelope, [dummySig(ethers.id('unknown'))])
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
                    UNSUPPORTED_ALGORITHM_ID,
                    encodedSignerAddress(f.signerA1.address),
                    TENANT_A,
                    0n
                )
            ).to.be.revertedWithCustomError(f.project, 'AlgorithmNotRegistered')
        })

        it('registering an unsupported algorithm reverts UnsupportedAlgorithm', async () => {
            const f = await deployFixture()
            await expect(
                f.project.connect(f.operator).registerAlgorithm(UNSUPPORTED_ALGORITHM_ID)
            ).to.be.revertedWithCustomError(f.project, 'UnsupportedAlgorithm')
        })

        it('registering a zero algorithm id reverts InvalidAlgorithmId', async () => {
            const f = await deployFixture()
            await expect(
                f.project.connect(f.operator).registerAlgorithm(ZERO_BYTES32)
            ).to.be.revertedWithCustomError(f.project, 'InvalidAlgorithmId')
        })

        it('registering a key against a disabled algorithm reverts AlgorithmDisabled', async () => {
            const f = await deployFixture()
            const op = f.project.connect(f.operator)
            await op.registerAlgorithm(ECDSA_ALGORITHM_ID)
            await op.setAlgorithmEnabled(ECDSA_ALGORITHM_ID, false)
            await expect(
                op.registerKey(
                    KEY_A1,
                    ECDSA_ALGORITHM_ID,
                    encodedSignerAddress(f.signerA1.address),
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
            await op.registerAlgorithm(ECDSA_ALGORITHM_ID)
            await expect(
                op.registerAlgorithm(ECDSA_ALGORITHM_ID)
            ).to.be.revertedWithCustomError(f.project, 'AlgorithmAlreadyRegistered')
        })
    })

    describe('Envelope validation', () => {
        it('zero eventHash reverts InvalidEventHash', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope({ eventHash: ZERO_BYTES32 })
            await expect(
                f.project.connect(f.operator).anchor(envelope, [dummySig(KEY_A1)])
            ).to.be.revertedWithCustomError(f.project, 'InvalidEventHash')
        })

        it('zero nonce reverts InvalidNonce', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope({ nonce: ZERO_BYTES32 })
            await expect(
                f.project.connect(f.operator).anchor(envelope, [dummySig(KEY_A1)])
            ).to.be.revertedWithCustomError(f.project, 'InvalidNonce')
        })

        it('zero schemaHash reverts InvalidSchemaHash', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope({ schemaHash: ZERO_BYTES32 })
            await expect(
                f.project.connect(f.operator).anchor(envelope, [dummySig(KEY_A1)])
            ).to.be.revertedWithCustomError(f.project, 'InvalidSchemaHash')
        })

        it('zero eip712TypeHash reverts InvalidEip712TypeHash', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope({ eip712TypeHash: ZERO_BYTES32 })
            await expect(
                f.project.connect(f.operator).anchor(envelope, [dummySig(KEY_A1)])
            ).to.be.revertedWithCustomError(f.project, 'InvalidEip712TypeHash')
        })

        it('zero tenantId reverts InvalidTenantId', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope({ tenantId: ZERO_BYTES32 })
            await expect(
                f.project.connect(f.operator).anchor(envelope, [dummySig(KEY_A1)])
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
                    await f.project.verifySignature(malformed, dummySig(KEY_A1))
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

            const offchain = ethers.TypedDataEncoder.hash(
                await eip712Domain(f.project),
                AUDIT_ENVELOPE_TYPES,
                envelope
            )
            expect(d1).to.equal(offchain)
        })

        it('digest changes when verifyingContract changes', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)

            const AuditServiceTestWrapper = await ethers.getContractFactory(
                'AuditServiceTestWrapper'
            )
            const other =
                (await AuditServiceTestWrapper.deploy()) as unknown as AuditServiceTestWrapper
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

        it('valid native ECDSA signature makes verifySignature true and anchor succeed', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope()
            const sig = await signedSig(f, KEY_A1, envelope)
            expect(await f.project.verifySignature(envelope, sig)).to.equal(true)
            await expect(
                f.project.connect(f.operator).anchor(envelope, [sig])
            ).to.emit(f.project, 'AuditAnchored')
        })

        it('wrong ECDSA signer makes verifySignature false and anchor revert InvalidSignature', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope({ eventHash: ethers.id('event.bad') })
            const sig = await signedSig(f, KEY_A1, envelope, f.wrongSigner)

            expect(await f.project.verifySignature(envelope, sig)).to.equal(false)

            await expect(
                f.project.connect(f.operator).anchor(envelope, [sig])
            ).to.be.revertedWithCustomError(f.project, 'InvalidSignature')

            expect(await f.project.exists(envelope.eventHash)).to.equal(false)
        })

        it('malformed ECDSA signature makes verifySignature false and anchor revert InvalidSignature', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope({ eventHash: ethers.id('event.malformed') })
            const sig = dummySig(KEY_A1, MALFORMED_SIG)

            expect(await f.project.verifySignature(envelope, sig)).to.equal(false)

            await expect(
                f.project.connect(f.operator).anchor(envelope, [sig])
            ).to.be.revertedWithCustomError(f.project, 'InvalidSignature')

            expect(await f.project.exists(envelope.eventHash)).to.equal(false)
        })

        it('verifySignatures returns per-signature booleans', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            const envelope = makeEnvelope()
            const valid = await signedSig(f, KEY_A1, envelope)
            const invalid = await signedSig(f, KEY_A2, envelope, f.wrongSigner)
            const results = await f.project.verifySignatures(envelope, [valid, invalid])
            expect(results[0]).to.equal(true)
            expect(results[1]).to.equal(false)
        })
    })

    describe('Pausing', () => {
        it('whenNotPaused functions revert while paused', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            await f.project.pauseForTest()

            const envelope = makeEnvelope()
            await expect(
                f.project.connect(f.operator).anchor(envelope, [dummySig(KEY_A1)])
            ).to.be.reverted

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

            await expect(
                f.project.connect(f.operator).revokeKey(KEY_A1)
            ).to.be.reverted
        })

        it('view functions stay callable while paused', async () => {
            const f = await deployFixture()
            await bootstrapHappyPath(f)
            await f.project.pauseForTest()
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
                f.project.connect(f.stranger).registerAlgorithm(ECDSA_ALGORITHM_ID)
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
                        ECDSA_ALGORITHM_ID,
                        encodedSignerAddress(f.signerA1.address),
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
                f.project.connect(f.stranger).anchor(envelope, [dummySig(KEY_A1)])
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
                    .setAlgorithmEnabled(ECDSA_ALGORITHM_ID, false)
            ).to.be.reverted
        })
    })

    describe('Metadata', () => {
        it('version() returns the EIP-712 domain version constant', async () => {
            const f = await deployFixture()
            expect(await f.project.version()).to.equal(EIP712_DOMAIN_VERSION)
        })

        it('eip712Domain returns name, version and verifyingContract', async () => {
            const f = await deployFixture()
            const [, name, version_, , verifyingContract] =
                await f.project.eip712Domain()
            expect(name).to.equal(EIP712_DOMAIN_NAME)
            expect(version_).to.equal(EIP712_DOMAIN_VERSION)
            expect(verifyingContract).to.equal(await f.project.getAddress())
        })
    })
})
