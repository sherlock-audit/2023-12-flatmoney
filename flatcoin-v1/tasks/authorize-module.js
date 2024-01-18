const { task } = require("hardhat/config");

task("authorize-module", "Adds an authorized module to a vault")
    .addParam("vault", "The address of the vault")
    .addParam("key", "The name of the module")
    .addParam("address", "The address of the module")
    .setAction(async (taskArgs, hre) => {
        await hre.run("compile");

        const deployer = (await hre.ethers.getSigners())[0];

        console.log(`Authorizing ${taskArgs.key} with the account:`, deployer.address);

        const flatcoinVault = await hre.ethers.getContractAt("FlatcoinVault", taskArgs.vault);

        await flatcoinVault.addAuthorizedModule({
            moduleKey: hre.ethers.utils.formatBytes32String(taskArgs.key),
            moduleAddress: taskArgs.address,
        });

        console.log(`${taskArgs.key} authorized!`);
    });
