import assert from 'node:assert'

import type { DeployFunction } from 'hardhat-deploy/types'

const contractName = 'TRWA'

const deploy: DeployFunction = async (hre) => {
    const { getNamedAccounts, deployments } = hre

    const { deploy } = deployments
    const { deployer } = await getNamedAccounts()

    assert(deployer, 'Missing named deployer account')

    console.log(`Network: ${hre.network.name}`)
    console.log(`Deployer: ${deployer}`)
    const endpointV2Deployment = await hre.deployments.get('EndpointV2')

    
    const { address } = await deploy(contractName, {
        from: deployer,
        args: [
            'TRWA', // name
            'TRWA', // symbol
            endpointV2Deployment.address, // LayerZero's EndpointV2 address
            deployer, // owner
        ],
        log: true,
        skipIfAlreadyDeployed: false,
    })

    console.log(`Deployed contract: ${contractName}, network: ${hre.network.name}, address: ${address}`)
}

deploy.tags = [contractName]

export default deploy
