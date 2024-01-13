async function main() {
    console.log("Testnet contracts deployment started...");

    const flatcoinVaultAddress = await hre.run("deploy-module", {
        module: "FlatcoinVault",
        path: "scripts/deployment/configs/FlatcoinVault.config.js",
        upgradeable: true,
    });

    const flatcoinVault = await ethers.getContractAt("FlatcoinVault", flatcoinVaultAddress);

    // Update the config files with the deployed vault address.
    await hre.run("modify-config", {
        path: "scripts/deployment/configs/StableModule.config.js",
        object: JSON.stringify({
            vault: flatcoinVaultAddress,
        }),
    });

    await hre.run("modify-config", {
        path: "scripts/deployment/configs/LeverageModule.config.js",
        object: JSON.stringify({
            vault: flatcoinVaultAddress,
        }),
    });

    await hre.run("modify-config", {
        path: "scripts/deployment/configs/OracleModule.config.js",
        object: JSON.stringify({
            vault: flatcoinVaultAddress,
        }),
    });

    await hre.run("modify-config", {
        path: "scripts/deployment/configs/LiquidationModule.config.js",
        object: JSON.stringify({
            vault: flatcoinVaultAddress,
        }),
    });

    await hre.run("modify-config", {
        path: "scripts/deployment/configs/Viewer.config.js",
        object: JSON.stringify({
            vault: flatcoinVaultAddress,
        }),
    });

    // Deploy the stable module.
    const stableModuleAddress = await hre.run("deploy-module", {
        module: "StableModule",
        path: "scripts/deployment/configs/StableModule.config.js",
        upgradeable: true,
    });

    // Deploy the leverage module.
    const leverageModuleAddress = await hre.run("deploy-module", {
        module: "LeverageModule",
        path: "scripts/deployment/configs/LeverageModule.config.js",
        upgradeable: true,
    });

    // Deploy the oracle module.
    const oracleModuleAddress = await hre.run("deploy-module", {
        module: "OracleModule",
        path: "scripts/deployment/configs/OracleModule.config.js",
        upgradeable: true,
    });

    // Deploy the liquidation module.
    const liquidationModuleAddress = await hre.run("deploy-module", {
        module: "LiquidationModule",
        path: "scripts/deployment/configs/LiquidationModule.config.js",
        upgradeable: true,
    });

    // Deploy the Viewer contract.
    // This module is not upgradeable and need not be authorized.
    await hre.run("deploy-module", {
        module: "Viewer",
        path: "scripts/deployment/configs/Viewer.config.js",
        upgradeable: false,
    });

    // Update the config files with the deployed oracle module addresses.
    await hre.run("modify-config", {
        path: "scripts/deployment/configs/KeeperFee.config.js",
        object: JSON.stringify({
            owner: (await hre.ethers.getSigners())[0].address,
            oracleModule: oracleModuleAddress,
        }),
    });

    // Deploy the keeper fee contract.
    const keeperFeeAddress = await hre.run("deploy-module", {
        module: "KeeperFee",
        path: "scripts/deployment/configs/KeeperFee.config.js",
        upgradeable: false,
    });

    // Update the config file with the vault and keeper fee address.
    await hre.run("modify-config", {
        path: "scripts/deployment/configs/DelayedOrder.config.js",
        object: JSON.stringify({
            vault: flatcoinVaultAddress,
        }),
    });

    // Deploy the delayed order contract.
    const delayedOrderAddress = await hre.run("deploy-module", {
        module: "DelayedOrder",
        path: "scripts/deployment/configs/DelayedOrder.config.js",
        upgradeable: true,
    });

    // Update the config file with the vault and keeper fee address.
    await hre.run("modify-config", {
        path: "scripts/deployment/configs/LimitOrder.config.js",
        object: JSON.stringify({
            vault: flatcoinVaultAddress,
        }),
    });

    // Deploy the delayed order contract.
    const limitOrderAddress = await hre.run("deploy-module", {
        module: "LimitOrder",
        path: "scripts/deployment/configs/LimitOrder.config.js",
        upgradeable: true,
    });

    // Authorize the modules.
    await flatcoinVault.addAuthorizedModules([
        {
            moduleKey: hre.ethers.utils.formatBytes32String("stableModule"),
            moduleAddress: stableModuleAddress,
        },
        {
            moduleKey: hre.ethers.utils.formatBytes32String("leverageModule"),
            moduleAddress: leverageModuleAddress,
        },
        {
            moduleKey: hre.ethers.utils.formatBytes32String("oracleModule"),
            moduleAddress: oracleModuleAddress,
        },
        {
            moduleKey: hre.ethers.utils.formatBytes32String("delayedOrder"),
            moduleAddress: delayedOrderAddress,
        },
        {
            moduleKey: hre.ethers.utils.formatBytes32String("limitOrder"),
            moduleAddress: limitOrderAddress,
        },
        {
            moduleKey: hre.ethers.utils.formatBytes32String("liquidationModule"),
            moduleAddress: liquidationModuleAddress,
        },
        {
            moduleKey: hre.ethers.utils.formatBytes32String("keeperFee"),
            moduleAddress: keeperFeeAddress,
        },
    ]);

    console.log("Modules authorized and deployment completed.");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
