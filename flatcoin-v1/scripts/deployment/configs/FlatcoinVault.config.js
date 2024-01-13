module.exports = {
    owner: "0x917A19E71a2811504C4f64aB33c132063B5772a5",
    WETH: "0xb36B6A4d67951C959CE22A8f30aF083fAc215088",
    maxFundingVelocity: "3000000000000000", // 0.003e18 (3% per day)
    maxVelocitySkew: "100000000000000000", // Max velocity at +-10% skew
    minExecutabilityAge: 5, // min order pending time
    maxExecutabilityAge: 60, // order expiry time
    stableCollateralCap: "500000000000000000000", // 500 ETH ~$1M
    skewFractionMax: "1200000000000000000", // 120% => 1.2
};
