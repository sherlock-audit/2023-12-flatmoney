const { task } = require("hardhat/config");
const { types } = require("hardhat/config");
const path = require("path");
const fs = require("fs");

task("modify-config", "Changes a config value")
    .addParam("path", "The path to the config file")
    .addParam("object", "The stringified object to add to the config file")
    .setAction(async (taskArgs, hre) => {
        await hre.run("compile");

        const configPath = path.join(__dirname, "..", taskArgs.path);
        const configObj = (await import(configPath)).default;

        const parsedObject = JSON.parse(taskArgs.object);
        console.log("Config object in modify:", parsedObject);

        // Traverse all the keys in the object and add them to the config object at the config path.
        for (const key in parsedObject) {
            // Check that the key exists in the config object and has an undefined value attached to it.
            // This prevents us from accidentally creating a new key in the config object or overwriting an existing key.
            if (!configObj.hasOwnProperty(key) && configObj[key] !== undefined) {
                console.error(`Key ${key} does not exist in config object.`);
                return;
            }

            configObj[key] = parsedObject[key];
        }

        const updatedModuleContents = `module.exports = ${JSON.stringify(configObj, null, 4)};\n`;

        try {
            fs.writeFileSync(configPath, updatedModuleContents);

            console.log(`Successfully updated config in ${path.basename(configPath)}`);
        } catch (error) {
            console.error(`Error writing to ${path.basename(configPath)}: ${error}`);
        }
    });
