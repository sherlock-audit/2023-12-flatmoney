const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");

const errorsFilePath = path.join(__dirname, "../../out/FlatcoinErrors.sol/FlatcoinErrors.json");

function main(selector) {
    const errorsData = fs.readFileSync(errorsFilePath, "utf8");
    const errorsJson = JSON.parse(errorsData);

    const errorObject = errorsJson.ast.nodes[2].nodes.find((node) => node.errorSelector === selector);

    return errorObject.name;
}

try {
    const slicedErrorSelector = process.argv[2].substring(2, 10);
    const errorName = main(slicedErrorSelector);
    console.log(errorName);
} catch (error) {
    console.error(error);
    process.exitCode = 1;
}
