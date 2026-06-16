import { HardhatUserConfig } from 'hardhat/config'
import '@nomicfoundation/hardhat-toolbox'
import dotenv from 'dotenv'
dotenv.config()

const config: HardhatUserConfig = {
    solidity: {
        version: '0.8.28',
        settings: {
            evmVersion: 'istanbul',
            optimizer: {
                enabled: true,
                runs: 200,
            },
        },
    },
    networks: {
        isbe: {
            url: process.env.LOCALHOST_URL ?? 'http://localhost:8545',
            accounts: process.env.ACCOUNT_PRIVATE_KEY
                ? [process.env.ACCOUNT_PRIVATE_KEY]
                : [],
        },
    },
}

export default config