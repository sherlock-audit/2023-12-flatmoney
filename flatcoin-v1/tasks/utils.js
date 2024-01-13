// Recursive function to convert values to nested arrays
const convertValuesToNestedArrays = (value) => {
    if (Array.isArray(value)) {
        // If the value is already an array, return it as is.
        return value;
    } else if (typeof value === "object") {
        // If the value is an object, recursively convert its values to nested arrays.
        const nestedArray = [];
        for (const key in value) {
            nestedArray.push(convertValuesToNestedArrays(value[key]));
        }
        return nestedArray;
    } else {
        // If the value is a primitive, just return it.
        return value;
    }
};

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const retryWithDelay = async (
    fn,
    functionType = "Function",
    retries = 3,
    interval = 5000,
    finalErr = Error("Retry failed"),
) => {
    try {
        return await fn();
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
    } catch (err) {
        console.log(`${functionType} call failed: ${err.message}`);
        if (retries <= 0) {
            return Promise.reject(finalErr);
        }
        await wait(interval);
        return retryWithDelay(fn, functionType, retries - 1, interval, finalErr);
    }
};

module.exports = {
    convertValuesToNestedArrays,
    wait,
    retryWithDelay,
};
