// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {ExpectRevert} from "../../helpers/ExpectRevert.sol";
import "../../helpers/OrderHelpers.sol";
import {FlatcoinErrors} from "src/libraries/FlatcoinErrors.sol";
import "src/interfaces/IChainlinkAggregatorV3.sol";

import "forge-std/console2.sol";

// TODO: Break the this file into multiple files.

contract MaxVelocitySkewTest is Setup, OrderHelpers, ExpectRevert {
    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);

        FlatcoinStructs.OnchainOracle memory onchainOracle = FlatcoinStructs.OnchainOracle(
            wethChainlinkAggregatorV3,
            type(uint32).max // Effectively disable oracle expiry.
        );
        FlatcoinStructs.OffchainOracle memory offchainOracle = FlatcoinStructs.OffchainOracle(
            IPyth(address(mockPyth)),
            0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace,
            60, // max age of 60 seconds
            1000
        );

        oracleModProxy.setOracle({
            _asset: address(WETH),
            _onchainOracle: onchainOracle,
            _offchainOracle: offchainOracle
        });
    }

    function test_max_velocity_skew_long() public {
        setWethPrice(1000e8);

        announceAndExecuteDepositAndLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            margin: 50e18,
            additionalSize: 120e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        vm.startPrank(admin);
        vaultProxy.setMaxFundingVelocity(0.003e18);
        vaultProxy.setMaxVelocitySkew(0.1e18);

        skip(1 days);

        // With 20% skew, the funding rate velocity should be at maximum
        assertEq(vaultProxy.getCurrentFundingRate(), 0.003e18, "Incorrect funding rate");
    }

    function test_max_velocity_skew_short() public {
        setWethPrice(1000e8);

        uint256 tokenId = announceAndExecuteDepositAndLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            margin: 50e18,
            additionalSize: 80e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        vm.startPrank(admin);
        vaultProxy.setMaxFundingVelocity(0.003e18);
        vaultProxy.setMaxVelocitySkew(0.01e18);

        skip(1 days);

        // With -20% skew, the funding rate velocity should be at maximum
        assertEq(vaultProxy.getCurrentFundingRate(), -0.003e18, "Incorrect funding rate");

        uint256 expectedStableCollateralPerShare = 1e18 - (((0.003e18 / 2) * 80) / 100);
        assertEq(
            stableModProxy.stableCollateralPerShare(),
            expectedStableCollateralPerShare,
            "Incorrect stable collateral per share"
        );

        vaultProxy.setExecutabilityAge(1, 60);

        announceAndExecuteLeverageClose({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        skip(1 days);

        int256 expectedFunding = -0.006e18 - (int256(0.003e18) / 1 days); // additional 1 second of funding for order exeution
        assertEq(vaultProxy.getCurrentFundingRate(), expectedFunding, "Incorrect funding rate");
    }

    function test_max_velocity_skew_long_half() public {
        setWethPrice(1000e8);

        announceAndExecuteDepositAndLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            margin: 50e18,
            additionalSize: 105e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        vm.startPrank(admin);
        vaultProxy.setMaxFundingVelocity(0.003e18);
        vaultProxy.setMaxVelocitySkew(0.1e18);

        skip(1 days);

        // With 5% skew, the funding rate velocity should be half the maximum
        assertEq(vaultProxy.getCurrentFundingRate(), 0.0015e18, "Incorrect funding rate");
    }

    function test_max_velocity_skew_short_half() public {
        setWethPrice(1000e8);

        announceAndExecuteDepositAndLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            margin: 50e18,
            additionalSize: 95e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        vm.startPrank(admin);
        vaultProxy.setMaxFundingVelocity(0.003e18);
        vaultProxy.setMaxVelocitySkew(0.1e18);

        skip(1 days);

        // With 5% skew, the funding rate velocity should be half the maximum
        assertEq(vaultProxy.getCurrentFundingRate(), -0.0015e18, "Incorrect funding rate");
    }
}
