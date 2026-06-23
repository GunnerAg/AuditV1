import { ethers } from 'hardhat'

type AuditEnvelope = {
  eventHash: string
  schemaId: string
  schemaVersion: string
  schemaHash: string
  eip712TypeHash: string
  tenantId: string
  status: number
  nonce: string
}

type SignatureInput = {
  keyId: string
  signature: string
}

const AUDIT_ENVELOPE_TYPE =
  'AuditEnvelope(bytes32 eventHash,bytes32 schemaId,bytes32 schemaVersion,bytes32 schemaHash,bytes32 eip712TypeHash,bytes32 tenantId,uint8 status,bytes32 nonce)'

const EIP712_NAME = 'Insurechain Audit Service'
const EIP712_VERSION = '1'
const ALGORITHM_ID = ethers.id('ECDSA_SECP256K1_EIP712')

function randomBytes32(label: string): string {
  return ethers.keccak256(
    ethers.solidityPacked(
      ['string', 'bytes32'],
      [label, ethers.hexlify(ethers.randomBytes(32))]
    )
  )
}

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) {
    throw new Error(message)
  }
}

async function expectRevert(label: string, action: () => Promise<unknown>) {
  let reverted = false

  try {
    await action()
  } catch {
    reverted = true
  }

  assert(reverted, `${label}: expected revert, but transaction succeeded`)
  console.log(`   OK revert: ${label}`)
}

async function ensureAlgorithm(audit: {
  getAlgorithm: (algorithmId: string) => Promise<{ enabled: boolean }>
  setAlgorithmEnabled: (algorithmId: string, enabled: boolean) => Promise<{ wait: () => Promise<unknown> }>
  registerAlgorithm: (algorithmId: string) => Promise<{ wait: () => Promise<unknown> }>
}) {
  try {
    const algorithm = await audit.getAlgorithm(ALGORITHM_ID)

    if (!algorithm.enabled) {
      const tx = await audit.setAlgorithmEnabled(ALGORITHM_ID, true)
      await tx.wait()
      console.log('   Algorithm existed but was disabled; enabled again')
    } else {
      console.log('   Algorithm already registered and enabled')
    }

    return
  } catch {
    const tx = await audit.registerAlgorithm(ALGORITHM_ID)
    await tx.wait()
    console.log('   Algorithm registered')
  }
}

async function main() {
  const proxy = process.env.AUDIT_SERVICE_PROXY

  if (!proxy || !ethers.isAddress(proxy)) {
    throw new Error(
      'Missing AUDIT_SERVICE_PROXY env var. Example: AUDIT_SERVICE_PROXY=0x... npx hardhat run ./scripts/project/validateAuditServiceFunctional.ts --network isbe'
    )
  }

  const [deployer] = await ethers.getSigners()
  const network = await ethers.provider.getNetwork()

  console.log('Functional validation for AuditService')
  console.log('-------------------------------------------------------------')
  console.log('Network chainId:', network.chainId.toString())
  console.log('Signer:', deployer.address)
  console.log('AuditService proxy:', proxy)
  console.log('-------------------------------------------------------------')

  const audit = await ethers.getContractAt('IAuditService', proxy, deployer)

  const code = await ethers.provider.getCode(proxy)
  assert(code !== '0x', 'Proxy has no bytecode')

  const domain = {
    name: EIP712_NAME,
    version: EIP712_VERSION,
    chainId: network.chainId,
    verifyingContract: proxy,
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

  console.log('\n[1/8] Checking EIP-712 domain...')
  const eip712Domain = await audit.eip712Domain()
  assert(eip712Domain.name === EIP712_NAME, 'Unexpected EIP-712 name')
  assert(eip712Domain.version === EIP712_VERSION || eip712Domain[2] === EIP712_VERSION, 'Unexpected EIP-712 version')
  assert(eip712Domain.verifyingContract === proxy || eip712Domain[4] === proxy, 'Unexpected verifyingContract')
  console.log('   EIP-712 domain OK')

  console.log('\n[2/8] Registering schema and algorithm...')
  const schemaId = randomBytes32('schemaId')
  const schemaVersion = ethers.encodeBytes32String('v1')
  const schemaBody = JSON.stringify({
    name: 'FunctionalAuditRecord',
    version: '1',
    fields: ['recordId', 'actor', 'action', 'resource', 'timestamp'],
  })
  const schemaHash = ethers.keccak256(ethers.toUtf8Bytes(schemaBody))
  const eip712TypeHash = ethers.id(AUDIT_ENVELOPE_TYPE)

  let tx = await audit.registerSchema(schemaId, schemaVersion, schemaHash, eip712TypeHash)
  await tx.wait()
  console.log('   Schema registered:', schemaId)

  await ensureAlgorithm(audit)

  console.log('\n[3/8] Registering signer key...')
  const tenantId = randomBytes32('tenantId')
  const keyId = randomBytes32('keyId')
  const publicKey = ethers.AbiCoder.defaultAbiCoder().encode(['address'], [deployer.address])

  tx = await audit.registerKey(keyId, ALGORITHM_ID, publicKey, tenantId, 0)
  await tx.wait()

  const key = await audit.getKey(keyId)
  assert(key.tenantId === tenantId, 'Registered key tenant mismatch')
  assert(await audit.isKeyActive(keyId), 'Registered key should be active')
  console.log('   Key registered:', keyId)

  console.log('\n[4/8] Creating audit record and EIP-712 envelope...')
  const auditRecord = {
    recordId: crypto.randomUUID(),
    actor: deployer.address,
    action: 'POLICY_STATUS_CHANGED',
    resource: 'policy:local-functional-test',
    timestamp: new Date().toISOString(),
  }

  const eventHash = ethers.keccak256(ethers.toUtf8Bytes(JSON.stringify(auditRecord)))

  const envelope: AuditEnvelope = {
    eventHash,
    schemaId,
    schemaVersion,
    schemaHash,
    eip712TypeHash,
    tenantId,
    status: 1,
    nonce: ethers.hexlify(ethers.randomBytes(32)),
  }

  const signature = await deployer.signTypedData(domain, types, envelope)
  const signatureInput: SignatureInput = { keyId, signature }

  console.log('   Event hash:', eventHash)
  console.log('   Signature:', signature.slice(0, 18) + '...')

  console.log('\n[5/8] Verifying EIP-712 signature...')
  const offchainDigest = ethers.TypedDataEncoder.hash(domain, types, envelope)
  const onchainDigest = await audit.hashEnvelope(envelope)

  assert(onchainDigest === offchainDigest, 'On-chain digest does not match off-chain EIP-712 digest')

  const valid = await audit.verifySignature(envelope, signatureInput)
  assert(valid === true, 'Expected valid EIP-712 signature')

  const batchResults = await audit.verifySignatures(envelope, [signatureInput])
  assert(batchResults.length === 1 && batchResults[0] === true, 'Expected batch verification true')

  console.log('   Digest matches on-chain/off-chain:', onchainDigest)
  console.log('   verifySignature OK')

  console.log('\n[6/8] Anchoring audit record...')
  tx = await audit.anchor(envelope, [signatureInput])
  const receipt = await tx.wait()
  assert(receipt?.status === 1, 'Anchor transaction failed')

  const exists = await audit.exists(eventHash)
  assert(exists === true, 'Anchored event should exist')

  const anchor = await audit.getAnchor(eventHash)
  assert(anchor.eventHash === eventHash, 'Anchor eventHash mismatch')
  assert(anchor.digest === onchainDigest, 'Anchor digest mismatch')
  assert(anchor.schemaId === schemaId, 'Anchor schemaId mismatch')
  assert(anchor.schemaVersion === schemaVersion, 'Anchor schemaVersion mismatch')
  assert(anchor.tenantId === tenantId, 'Anchor tenantId mismatch')
  assert(Number(anchor.status) === 1, 'Anchor status mismatch')
  assert(Number(anchor.signerCount) === 1, 'Anchor signerCount mismatch')

  console.log('   Anchor stored correctly')

  console.log('\n[7/8] Reading signer record...')
  const signerCount = await audit.getSignerCount(eventHash)
  assert(Number(signerCount) === 1, 'Expected exactly one signer')

  const signerRecord = await audit.getSigner(eventHash, keyId)
  const expectedCommitment = ethers.keccak256(signature)

  assert(signerRecord.keyId === keyId, 'Signer keyId mismatch')
  assert(signerRecord.algorithmId === ALGORITHM_ID, 'Signer algorithm mismatch')
  assert(signerRecord.signatureCommitment === expectedCommitment, 'Signature commitment mismatch')

  const hasSigner = await audit.hasSigner(eventHash, keyId)
  assert(hasSigner === true, 'Expected hasSigner true')

  console.log('   Signer record OK')

  console.log('\n[8/8] Negative/security checks...')

  const tamperedEnvelope: AuditEnvelope = {
    ...envelope,
    status: 2,
  }

  const tamperedValid = await audit.verifySignature(tamperedEnvelope, signatureInput)
  assert(tamperedValid === false, 'Tampered envelope should not validate')
  console.log('   OK: tampered envelope rejected')

  const wrongWallet = ethers.Wallet.createRandom()

  const badEnvelope: AuditEnvelope = {
    ...envelope,
    eventHash: randomBytes32('badEventHash'),
    nonce: ethers.hexlify(ethers.randomBytes(32)),
  }

  const wrongSignature = await wrongWallet.signTypedData(domain, types, badEnvelope)
  const wrongSignatureInput: SignatureInput = {
    keyId,
    signature: wrongSignature,
  }

  const wrongValid = await audit.verifySignature(badEnvelope, wrongSignatureInput)
  assert(wrongValid === false, 'Wrong signer should not validate')
  console.log('   OK: wrong signer rejected by verifySignature')

  await expectRevert('anchor with wrong signer', async () => {
    const badTx = await audit.anchor(badEnvelope, [wrongSignatureInput])
    await badTx.wait()
  })

  const wrongTenantEnvelope: AuditEnvelope = {
    ...envelope,
    eventHash: randomBytes32('wrongTenantEventHash'),
    tenantId: randomBytes32('wrongTenantId'),
    nonce: ethers.hexlify(ethers.randomBytes(32)),
  }

  const wrongTenantSignature = await deployer.signTypedData(domain, types, wrongTenantEnvelope)
  const wrongTenantValid = await audit.verifySignature(wrongTenantEnvelope, {
    keyId,
    signature: wrongTenantSignature,
  })

  assert(wrongTenantValid === false, 'Wrong tenant should not validate')
  console.log('   OK: wrong tenant rejected')

  await expectRevert('replay same eventHash', async () => {
    const replayTx = await audit.anchor(envelope, [signatureInput])
    await replayTx.wait()
  })

  console.log('\nFunctional validation complete!')
  console.log('-------------------------------------------------------------')
  console.log('Audit record eventHash:', eventHash)
  console.log('AuditService proxy:', proxy)
  console.log('EIP-712 digest:', onchainDigest)
  console.log('Signer keyId:', keyId)
  console.log('TenantId:', tenantId)
  console.log('-------------------------------------------------------------')
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
