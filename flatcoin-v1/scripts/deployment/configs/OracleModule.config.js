module.exports = {
    vault: "0x1c46c9110c22d9e693c0eE6E3c76F7244EA99d0a",
    WETH: "0xb36B6A4d67951C959CE22A8f30aF083fAc215088",
    onChainOracle: {
        chainlinkV3Aggregator: "0xcD2A119bD1F7DF95d706DE6F2057fDD45A0503E2",
        chainlinkPriceExpiry: 90000,
    },
    offchainOracle: {
        pyth: "0x5955c1478f0dad753c7e2b4dd1b4bc530c64749f",
        pythPriceFeedId: "0xca80ba6dc32e08d06f1aa886011eed1d77c77be9eb761cc10d72b7d0a2fd57a6",
        pythMaxPriceAge: 90000,
        pythMinConfidenceRatio: 1000,
    },
    maxDiffPercent: "5000000000000000",
};
