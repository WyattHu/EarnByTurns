const { network } = require("hardhat");
const {
    networkconfig,
    developmentChains,
} = require("../hardhat-config-helper");
require("dotenv").config();
const { verify } = require("../utility/verify");

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, log } = deployments;
    const { deployer,user1,user2 } = await getNamedAccounts();
    const chainId = network.config.chainId;
    let MultiSignWallet;
    log('chainId:' + chainId)
    log(deployer)
    log(user1)
    log(user2)
    log("Deploying MultiSignWallet Contract...");

    MultiSignWallet = await deploy("MultiSignWallet", {
        contract: "MultiSignWallet",
        from: deployer,
        log: true,
        args: [[deployer,user1,user2],2],
        waitConfirmations: network.config.blockConfirmations || 1,
    });


    log("------------------------------------------------");
    log(`MultiSignWallet deployed at ${MultiSignWallet.address}`);

    if (
        !developmentChains.includes(network.name) &&
        process.env.ETHERSCAN_API_KEY
    ) {
        await verify(MultiSignWallet.address, [[deployer,user1,user2],2]);
    }
};
module.exports.tags = ["all", "MultiSignWallet"];
