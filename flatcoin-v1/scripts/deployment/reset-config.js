const fs = require("fs");
const path = require("path");

// Define the directory containing the config files
const configDir = path.join(__dirname, "configs");

// Define the keys to be reset
const keysToReset = {
    vault: true,
    keeperFeeAddress: true,
};

function main() {
    // Loop through each file in the directory
    fs.readdirSync(configDir).forEach((file) => {
        let valuesReset;

        // Load the file as a JSON object
        const filePath = path.join(configDir, file);
        const config = require(filePath);

        // Loop through each key in the object
        for (const key in config) {
            // If the key is one of the keys to reset, set its value to undefined
            if (keysToReset[key]) {
                // Note that we are resetting the value to string 'undefined'
                // This is because, JSON.stringify will remove the key if the value is undefined.
                config[key] = "undefined";
                valuesReset = true;
            }
        }

        if (valuesReset) {
            const updatedModuleContents = `module.exports = ${JSON.stringify(config, null, 4)};\n`;

            // Write the modified object back to the file
            fs.writeFileSync(filePath, updatedModuleContents);
        }
    });
}

try {
    console.log("\nResetting config values...");
    main();
    console.log("Config values reset!\n");
} catch (error) {
    console.error("Error resetting config values:", error);
}
