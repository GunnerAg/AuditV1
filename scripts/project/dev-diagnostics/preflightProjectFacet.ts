import { ethers } from 'hardhat'

const CTB_PROJECT_RESOLVER_KEY = ethers.id(
    'isbe.customers.ctb.audit-service.v1.resolver.key'
)

const GENERIC_PROJECT_RESOLVER_KEY =
    '0xb4417cc44e05188951b5cfb2e3c50fc55c32aef75d6cba6bace701e21a83e8e8'

const CTB_PROJECT_CONFIG_ID = ethers.id(
    'isbe.customers.ctb.audit-service.v1.configuration'
)

const GENERIC_PROJECT_CONFIG_ID =
    '0x5f63bb9fbe719c0975430a4152f0ef5f2337692814ad0be2e7616b7d632800fb'

async function main() {
    const [signer] = await ethers.getSigners()
    const network = await ethers.provider.getNetwork()

    console.log('Account:', signer.address)
    console.log('Chain ID:', network.chainId.toString())

    console.log('\nExpected IDs from CTB constants.sol strings:')
    console.log('CTB_PROJECT_RESOLVER_KEY:', CTB_PROJECT_RESOLVER_KEY)
    console.log('CTB_PROJECT_CONFIG_ID:  ', CTB_PROJECT_CONFIG_ID)

    console.log('\nLegacy generic IDs currently in reverted project script:')
    console.log('GENERIC_PROJECT_RESOLVER_KEY:', GENERIC_PROJECT_RESOLVER_KEY)
    console.log('GENERIC_PROJECT_CONFIG_ID:  ', GENERIC_PROJECT_CONFIG_ID)

    const ProjectFacet = await ethers.getContractFactory('ProjectFacet')
    const projectFacet = await ProjectFacet.deploy()
    await projectFacet.waitForDeployment()

    const facetAddress = await projectFacet.getAddress()
    const facetBusinessId = await projectFacet.businessIdIntrospection()
    const selectors = await projectFacet.selectorsIntrospection()
    const interfaces = await projectFacet.interfacesIntrospection()

    console.log('\nDirect ProjectFacet deployment:')
    console.log('ProjectFacet address:', facetAddress)
    console.log('businessIdIntrospection():', facetBusinessId)
    console.log('selectors length:', selectors.length)
    console.log('interfaces length:', interfaces.length)

    console.log('\nChecks:')
    console.log(
        'businessId == CTB_PROJECT_RESOLVER_KEY:',
        facetBusinessId === CTB_PROJECT_RESOLVER_KEY
    )
    console.log(
        'businessId == GENERIC_PROJECT_RESOLVER_KEY:',
        facetBusinessId === GENERIC_PROJECT_RESOLVER_KEY
    )

    if (facetBusinessId !== CTB_PROJECT_RESOLVER_KEY) {
        throw new Error('ProjectFacet businessId does not match CTB resolver key')
    }

    console.log('\nPreflight OK.')
}

main().catch((error) => {
    console.error(error)
    process.exit(1)
})