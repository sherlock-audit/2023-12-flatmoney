const { task } = require("hardhat/config");
const { types } = require("hardhat/config");
const { getImplementationAddress } = require("@openzeppelin/upgrades-core");
const path = require("path");
const { convertValuesToNestedArrays, retryWithDelay } = require("./utils");

task("deploy-module", "Deploys a Flatcoin upgradeable module")
    .addParam("module", "The name of the module to deploy")
    .addParam("path", "The path to the config file")
    .addOptionalParam("upgradeable", "Whether the module should be upgradeable", true, types.boolean)
    .setAction(async (taskArgs, hre) => {
        await hre.run("compile");

        const deployer = (await hre.ethers.getSigners())[0];

        console.log(`Deploying ${taskArgs.module} with the account:`, deployer.address);

        const ModuleFactory = await hre.ethers.getContractFactory(taskArgs.module);

        const configPath = path.join(__dirname, "..", taskArgs.path);

        // Get the config object from the config file.
        const configObj = convertValuesToNestedArrays((await import(configPath)).default);

        // Check that none of the config values are undefined.
        for (let key in configObj) {
            if (configObj[key] === "undefined" || configObj[key] === undefined) {
                throw new Error(`Config value ${key} is undefined!`);
            }
        }

        let module;

        // If the module is upgradeable, deploy it as an upgradeable proxy.
        // NOTE: We are assuming that upgradeable contracts don't have constructor arguments.
        //       If this is not the case, we will need to modify this part of the code.
        if (taskArgs.upgradeable) {
            module = await retryWithDelay(
                async () =>
                    await upgrades.deployProxy(ModuleFactory, configObj, {
                        kind: "transparent",
                    }),
            );
        } else {
            // module = await ModuleFactory.deploy(...configObj);
            module = await retryWithDelay(async () => await ModuleFactory.deploy(...configObj));
        }

        await module.deployed();

        console.log(`${taskArgs.module} deployed to:`, module.address);

        // Verify the module on Etherscan.
        // If the module is upgradeable, we need to verify the implementation contract.
        // NOTE: We are assuming that upgradeable contracts don't have constructor arguments.
        try {
            if (taskArgs.upgradeable) {
                await retryWithDelay(
                    async () =>
                        await hre.run("verify:verify", {
                            address: await getImplementationAddress(hre.ethers.provider, module.address),
                        }),
                );
            } else {
                await retryWithDelay(
                    async () =>
                        await hre.run("verify:verify", {
                            address: module.address,
                            constructorArguments: configObj,
                        }),
                );
            }

            console.log(`${taskArgs.module} verified!`);
        } catch (error) {
            console.error(`Error encountered while verifying ${taskArgs.module}:`);
        }

        return module.address;
    });
