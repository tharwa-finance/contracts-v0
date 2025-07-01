// Get the environment configuration from .env file
//
// To make use of automatic environment setup:
// - Duplicate .env.example file and name it .env
// - Fill in the environment variables
import 'dotenv/config'

import 'hardhat-deploy'
import 'hardhat-contract-sizer'
import '@nomiclabs/hardhat-ethers'
import '@layerzerolabs/toolbox-hardhat'
import type { HardhatUserConfig, HttpNetworkAccountsUserConfig } from 'hardhat/types'

import { EndpointId } from '@layerzerolabs/lz-definitions'

const PRIVATE_KEY = process.env.PRIVATE_KEY

const accounts: HttpNetworkAccountsUserConfig | undefined = PRIVATE_KEY
    ? [PRIVATE_KEY]
    : undefined

if (accounts == null) {
    console.warn(
        'Could not find PRIVATE_KEY environment variables. It will not be possible to execute transactions in your example.'
    )
}

const config: HardhatUserConfig = {
    paths: {
        cache: 'cache/hardhat',
    },

    solidity: {
        compilers: [
            {
                version: '0.8.24',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
        ],
    },
    networks: {
        'sepolia-testnet': {
            eid: EndpointId.SEPOLIA_V2_TESTNET,
            url: 'https://sepolia.drpc.org',
            accounts,
        },
        'eth-mainnet': {
            eid: EndpointId.ETHEREUM_V2_MAINNET,
            url: 'https://eth.merkle.io',
            gas: 6000000,
            gasPrice: "auto",
            accounts,
        },
        'holesky-testnet': {
            eid: EndpointId.HOLESKY_V2_TESTNET,
            url: 'https://holesky.drpc.org',
            accounts,
        },

        hardhat: {

            // Need this for testing because TestHelperOz5.sol is exceeding the compiled contract size limit
            allowUnlimitedContractSize: true,
        },
    },
    namedAccounts: {
        deployer: {
            default: 0,
        },
    },
}

export default config
