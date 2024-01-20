// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {IPyth} from "pyth-sdk-solidity/IPyth.sol";

import "../../../helpers/Setup.sol";
import "../../../helpers/OrderHelpers.sol";

import "forge-std/console2.sol";

contract GetFlatcoinPriceInUSDTest is Setup, OrderHelpers {
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

    function test_viewer_flatcoin_price_in_usd_when_no_deposit() public {
        setWethPrice(1e8);

        uint256 priceInUsd = viewer.getFlatcoinPriceInUSD();
        assertEq(priceInUsd, 1e18, "Incorrect price in USD when no deposits");

        setWethPrice(4242e8);

        priceInUsd = viewer.getFlatcoinPriceInUSD();
        assertEq(priceInUsd, 4242e18, "Incorrect price in USD when no deposits");

        setWethPrice(1_000_000_000e8);

        priceInUsd = viewer.getFlatcoinPriceInUSD();
        assertEq(priceInUsd, 1_000_000_000e18, "Incorrect price in USD when no deposits");
    }

    function test_viewer_flatcoin_price_in_usd_when_single_deposit() public {
        vm.startPrank(alice);

        setWethPrice(1000e8);

        uint256 depositAmount = 100e18;
        uint256 collateralPrice = 1000e8;

        // First deposit mint doesn't use offchain oracle price
        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: depositAmount,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 priceInUsd = viewer.getFlatcoinPriceInUSD();
        assertEq(priceInUsd, 1000e18, "Incorrect price in USD when single deposit");

        setWethPrice(4242e8);

        priceInUsd = viewer.getFlatcoinPriceInUSD();
        assertEq(priceInUsd, 4242e18, "Incorrect price in USD when single deposit");

        setWethPrice(1_000_000_000e8);

        priceInUsd = viewer.getFlatcoinPriceInUSD();
        assertEq(priceInUsd, 1_000_000_000e18, "Incorrect price in USD when single deposit");
    }

    function test_viewer_flatcoin_price_in_usd_when_no_market_skew() public {
        setWethPrice(1000e8);

        // Disable trading fees so that they don't impact the results
        vm.startPrank(admin);
        stableModProxy.setStableWithdrawFee(0);
        leverageModProxy.setLevTradingFee(0);

        vm.startPrank(alice);

        // First deposit mint doesn't use offchain oracle price
        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        // 2x leverage position
        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 100e18,
            additionalSize: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        // Enabling funding rate now that skew is anyway 0.
        vm.startPrank(admin);
        vaultProxy.setMaxFundingVelocity(0.03e18);

        skip(2 days);

        uint256 priceInUsd = viewer.getFlatcoinPriceInUSD();
        assertEq(priceInUsd, 1000e18, "Incorrect price in USD when no market skew");
    }

    function test_viewer_flatcoin_price_in_usd_when_long_skewed_and_no_change_in_price() public {
        setWethPrice(1000e8);

        vm.startPrank(alice);

        // First deposit mint doesn't use offchain oracle price
        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        // 2.2x leverage position
        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 100e18,
            additionalSize: 120e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        // Enabling funding rate.
        vm.startPrank(admin);
        vaultProxy.setMaxFundingVelocity(0.03e18);

        uint256 priceInUsdBefore = viewer.getFlatcoinPriceInUSD();

        skip(2 days);

        uint256 priceInUsdAfter = viewer.getFlatcoinPriceInUSD();

        // The price has to be greater than before because of the funding fees
        // paid to the LPs by longs.
        assertGt(
            priceInUsdAfter,
            priceInUsdBefore,
            "Price in USD should have increased when long skewed and no change in collateral price"
        );
    }

    function test_viewer_flatcoin_price_in_usd_when_stable_skewed_and_no_change_in_price() public {
        setWethPrice(1000e8);

        vm.startPrank(alice);

        // First deposit mint doesn't use offchain oracle price
        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        // 2x leverage position
        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 50e18,
            additionalSize: 50e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        // Enabling funding rate.
        vm.startPrank(admin);
        vaultProxy.setMaxFundingVelocity(0.03e18);

        uint256 priceInUsdBefore = viewer.getFlatcoinPriceInUSD();

        skip(2 days);

        uint256 priceInUsdAfter = viewer.getFlatcoinPriceInUSD();

        // The price has to be lesser than before because of the funding fees
        // paid to the longs by LPs.
        assertLt(
            priceInUsdAfter,
            priceInUsdBefore,
            "Price in USD should have decreased when stable skewed and no change in collateral price"
        );
    }

    function test_viewer_flatcoin_price_in_usd_when_long_skewed_and_price_increases() public {
        setWethPrice(1000e8);

        vm.startPrank(alice);

        // First deposit mint doesn't use offchain oracle price
        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        // 2.2x leverage position
        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 100e18,
            additionalSize: 120e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        // Enabling funding rate.
        vm.startPrank(admin);
        vaultProxy.setMaxFundingVelocity(0.03e18);

        uint256 priceInUsdBefore = viewer.getFlatcoinPriceInUSD();

        skip(2 days);

        // WETH price has doubled.
        setWethPrice(2000e8);

        uint256 priceInUsdAfter = viewer.getFlatcoinPriceInUSD();

        // The price has to be lesser than before because of the profits gained by longs.
        // The funding fees paid by longs are offset by the profits gained by longs.
        assertLt(
            priceInUsdAfter,
            priceInUsdBefore,
            "Price in USD should have decreased when long skewed and collateral price increases"
        );
    }

    function test_viewer_flatcoin_price_in_usd_when_long_skewed_and_price_decreases() public {
        setWethPrice(1000e8);

        vm.startPrank(alice);

        // First deposit mint doesn't use offchain oracle price
        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        // 2.2x leverage position
        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 100e18,
            additionalSize: 120e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        // Enabling funding rate.
        vm.startPrank(admin);
        vaultProxy.setMaxFundingVelocity(0.03e18);

        uint256 priceInUsdBefore = viewer.getFlatcoinPriceInUSD();

        skip(2 days);

        // WETH price has reduced by 20%.
        setWethPrice(800e8);

        uint256 priceInUsdAfter = viewer.getFlatcoinPriceInUSD();

        // The price has to be greater than before because of the losses incurred by longs.
        // and funding fees paid by longs.
        assertGt(
            priceInUsdAfter,
            priceInUsdBefore,
            "Price in USD should have increased when long skewed and collateral price decreases"
        );
    }

    function test_viewer_flatcoin_price_in_usd_when_stable_skewed_and_price_increases() public {
        setWethPrice(1000e8);

        vm.startPrank(alice);

        // First deposit mint doesn't use offchain oracle price
        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        // 2x leverage position
        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 50e18,
            additionalSize: 50e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        // Enabling funding rate.
        vm.startPrank(admin);
        vaultProxy.setMaxFundingVelocity(0.03e18);

        uint256 priceInUsdBefore = viewer.getFlatcoinPriceInUSD();

        skip(2 days);

        setWethPrice(2000e8);

        uint256 priceInUsdAfter = viewer.getFlatcoinPriceInUSD();

        // Since the market is stable skewed, the price of the WETH impacts the price
        // of the flatcoin. The price of the flatcoin should increase because of the direct correlation
        // with the price of WETH. However, It won't be equal to the price of WETH because of the profits
        // gained by the longs and the funding fees paid by the LPs.
        assertTrue(
            priceInUsdAfter > priceInUsdBefore && priceInUsdAfter < 2000e18,
            "Price in USD should have increased but not equal to WETH price"
        );
    }

    function test_viewer_flatcoin_price_in_usd_when_stable_skewed_and_price_decreases() public {
        setWethPrice(1000e8);

        vm.startPrank(alice);

        // First deposit mint doesn't use offchain oracle price
        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        // 2x leverage position
        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 50e18,
            additionalSize: 50e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        // Enabling funding rate.
        vm.startPrank(admin);
        vaultProxy.setMaxFundingVelocity(0.03e18);

        uint256 priceInUsdBefore = viewer.getFlatcoinPriceInUSD();

        skip(2 days);

        // Price has been reduced by 50%.
        setWethPrice(500e8);

        uint256 priceInUsdAfter = viewer.getFlatcoinPriceInUSD();

        // Since the market is stable skewed, the price of the WETH impacts the price
        // of the flatcoin. The price of the flatcoin should decrease because of the direct correlation
        // with the price of WETH. However, It won't be equal to the price of WETH because of the losses
        // incurred by the longs.
        assertTrue(
            priceInUsdAfter < priceInUsdBefore && priceInUsdAfter > 500e18,
            "Flatcoin price should have decreased but not equal to WETH price"
        );
    }
}
