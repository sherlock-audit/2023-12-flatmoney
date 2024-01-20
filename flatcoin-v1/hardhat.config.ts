import dotenv from "dotenv";
dotenv.config();
import "hardhat-preprocessor";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";
import "hardhat-abi-exporter";
import "@openzeppelin/hardhat-upgrades";
import "@openzeppelin/hardhat-defender";
import { HardhatUserConfig } from "hardhat/config";

import "./tasks/authorize-module.js";
import "./tasks/deploy-module.js";
import "./tasks/modify-config.js";
import "./tasks/upgrade-module.js";

const config: HardhatUserConfig = {
    solidity: {
        version: "0.8.18",
        settings: {
            optimizer: {
                enabled: true,
                runs: 500,
            },
        },
    },
    networks: {
        localhost: {
            chainId: 31337,
            url: "http://127.0.0.1:8545",
            timeout: 0,
            accounts: process.env.BASE_GOERLI_PRIVATE_KEY ? [process.env.BASE_GOERLI_PRIVATE_KEY] : [],
        },
        optimism: {
            chainId: 10,
            url: process.env.OPTIMISM_RPC_URL || "https://opt-mainnet.g.alchemy.com/v2/",
            accounts: process.env.OPTIMISM_PRIVATE_KEY ? [process.env.OPTIMISM_PRIVATE_KEY] : [],
        },
        ethereum: {
            chainId: 1,
            url: process.env.ETHEREUM_RPC_URL || "https://eth-mainnet.g.alchemy.com/v2/",
            accounts: process.env.ETHEREUM_PRIVATE_KEY ? [process.env.ETHEREUM_PRIVATE_KEY] : [],
        },
        optimisticGoerli: {
            chainId: 420,
            url: process.env.OPTIMISM_GOERLI_RPC_URL || "https://goerli.optimism.io",
            accounts: process.env.OPTIMISM_GOERLI_PRIVATE_KEY ? [process.env.OPTIMISM_GOERLI_PRIVATE_KEY] : [],
        },
        // NOTE: The following configuration uses legacy transactions. For mainnet, change the configuration to use EIP-1559.
        baseGoerli: {
            chainId: 84531,
            url: process.env.BASE_GOERLI_RPC_URL || "https://goerli.base.org",
            accounts: process.env.BASE_GOERLI_PRIVATE_KEY ? [process.env.BASE_GOERLI_PRIVATE_KEY] : [],
            blockGasLimit: 25000000,
            gasPrice: 2000000000, // 2 gwei
            loggingEnabled: true,
        },
    },
    etherscan: {
        // https://hardhat.org/plugins/nomiclabs-hardhat-etherscan.html#multiple-api-keys-and-alternative-block-explorers
        apiKey: {
            mainnet: process.env.ETHERSCAN_API_KEY!,
            optimisticEthereum: process.env.OPTIMISTIC_ETHERSCAN_API_KEY!,
            optimisticGoerli: process.env.OPTIMISTIC_ETHERSCAN_API_KEY!,
            baseGoerli: process.env.BASE_ETHERSCAN_API_KEY!,
        },
        customChains: [
            {
                network: "baseGoerli",
                chainId: 84531,
                urls: {
                    apiURL: "https://api-goerli.basescan.org/api",
                    browserURL: "https://goerli.basescan.org/",
                },
            },
        ],
    },
    abiExporter: {
        except: ["lib"],
        runOnCompile: true,
    },
    defender: {
        apiKey: process.env.DEFENDER_API_KEY!,
        apiSecret: process.env.DEFENDER_SECRET_KEY!,
    },
};

export default config;
