require("hardhat-deploy");
require("dotenv").config();
require("@nomicfoundation/hardhat-verify");
require("@nomicfoundation/hardhat-ethers");
require("hardhat-deploy-ethers");
require("solidity-coverage");
require("@nomicfoundation/hardhat-chai-matchers");

const SEPOLIA_RPC_URL = process.env.SEPOLIA_RPC_URL;
const PRIVATE_KEY1 = process.env.PRIVATE_KEY1;
const PRIVATE_KEY2 = process.env.PRIVATE_KEY2;
const PRIVATE_KEY3 = process.env.PRIVATE_KEY3;
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    solidity: {
        compilers: [
            {
                version: "0.8.20",
            },
        ],
    },
    defaultNetwork: "hardhat",
    networks: {
        hardhat: {
            chainId: 31337,
        },
        sepolia: {
            url: SEPOLIA_RPC_URL,
            accounts: [PRIVATE_KEY1,PRIVATE_KEY2,PRIVATE_KEY3],
            chainId: 11155111,
            blockConfirmations: 2,
        },
    },
    namedAccounts: {
        deployer: {
            default: 0,
            11155111: 0,
        },
        user1: {
            default: 1,
            11155111: 1,
        },
        user2:{
            default: 2,
            11155111: 2,
        },
        user3:{
            default: 3,
        }
    },
    etherscan: {
        apiKey: ETHERSCAN_API_KEY,
    },
};
