const { task } = require("hardhat/config")

task("block-time", "Print the current block time").setAction(async (args, her) => {
    const blockTime = await (await her.ethers.provider.getBlock()).timestamp
    console.log(`Current block time: ${blockTime}`)
})
