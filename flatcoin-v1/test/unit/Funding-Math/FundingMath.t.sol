// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {ExpectRevert} from "../../helpers/ExpectRevert.sol";
import "../../helpers/OrderHelpers.sol";
import {FlatcoinErrors} from "src/libraries/FlatcoinErrors.sol";
import "src/interfaces/IChainlinkAggregatorV3.sol";

import "forge-std/console2.sol";

// TODO: Break the this file into multiple files.

contract FundingMathTest is Setup, OrderHelpers, ExpectRevert {
    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);

        vaultProxy.setMaxFundingVelocity(0.03e18);

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

    function test_pnl_no_price_change_long_skew() public {
        vm.startPrank(alice);

        uint256 aliceBalanceBefore = WETH.balanceOf(alice);
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });
        // 10 ETH collateral, 30 ETH additional size (4x leverage)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });
        // 70 ETH collateral, 70 ETH additional size (2x leverage)
        uint256 tokenId2 = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 70e18,
            additionalSize: 70e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        assertEq(leverageModProxy.getPositionSummary(tokenId).profitLoss, 0, "PnL for position 1 should be 0");
        assertEq(leverageModProxy.getPositionSummary(tokenId2).profitLoss, 0, "PnL for position 2 should be 0");

        skip(2 days);

        // Close first position
        announceAndExecuteLeverageClose({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // Close second position
        announceAndExecuteLeverageClose({
            tokenId: tokenId2,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // The amount received after closing the positions should be lesser than amount deposited as
        // margin due to losses from funding payments.
        assertLt(
            WETH.balanceOf(alice),
            aliceBalanceBefore - stableDeposit,
            "Alice's should receive more than her total margin"
        );
    }

    function test_pnl_no_price_change_short_skew() public {
        vm.startPrank(alice);

        uint256 aliceBalanceBefore = WETH.balanceOf(alice);
        uint256 stableDeposit = 200e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });
        // 10 ETH collateral, 30 ETH additional size (4x leverage)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });
        // 70 ETH collateral, 70 ETH additional size (2x leverage)
        uint256 tokenId2 = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 70e18,
            additionalSize: 70e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        assertEq(leverageModProxy.getPositionSummary(tokenId).profitLoss, 0, "PnL for position 1 should be 0");
        assertEq(leverageModProxy.getPositionSummary(tokenId2).profitLoss, 0, "PnL for position 2 should be 0");

        skip(2 days);

        // Close first position
        announceAndExecuteLeverageClose({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // Close second position
        announceAndExecuteLeverageClose({
            tokenId: tokenId2,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // The amount received after closing the positions should be greater than amount deposited as
        // collateral due to profit from funding payments.
        assertGt(
            WETH.balanceOf(alice),
            aliceBalanceBefore - stableDeposit,
            "Alice's should receive more than her total margin"
        );
    }

    function test_pnl_price_increase_long_skew() public {
        vm.startPrank(alice);

        uint256 aliceBalanceBefore = WETH.balanceOf(alice);
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });
        // 10 ETH collateral, 30 ETH additional size (4x leverage)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });
        // 70 ETH collateral, 70 ETH additional size (2x leverage)
        uint256 tokenId2 = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 70e18,
            additionalSize: 70e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // The price of ETH increases by 100%.
        uint256 newCollateralPrice = 2000e8;
        setWethPrice(newCollateralPrice);

        int256 pnl1 = leverageModProxy.getPositionSummary(tokenId).profitLoss;
        int256 pnl2 = leverageModProxy.getPositionSummary(tokenId2).profitLoss;

        assertEq(pnl1, 15e18, "PnL for position 1 is incorrect");
        assertEq(pnl2, 35e18, "PnL for position 2 is incorrect");

        skip(2 days);

        // Close first position
        announceAndExecuteLeverageClose({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        // Close second position
        announceAndExecuteLeverageClose({
            tokenId: tokenId2,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        // The amount received after closing the positions should be lesser than margin deposited + profit from
        // price increase due to losses from funding payments.
        assertLt(
            WETH.balanceOf(alice),
            aliceBalanceBefore - stableDeposit + uint256(pnl1) + uint256(pnl2),
            "Alice should have profits after closing positions with price increase"
        );
    }

    function test_pnl_price_increase_short_skew() public {
        vm.startPrank(alice);

        uint256 aliceBalanceBefore = WETH.balanceOf(alice);
        uint256 stableDeposit = 200e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });
        // 10 ETH collateral, 30 ETH additional size (4x leverage)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });
        // 70 ETH collateral, 70 ETH additional size (2x leverage)
        uint256 tokenId2 = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 70e18,
            additionalSize: 70e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // The price of ETH increases by 100%.
        uint256 newCollateralPrice = 2000e8;
        setWethPrice(newCollateralPrice);

        int256 pnl1 = leverageModProxy.getPositionSummary(tokenId).profitLoss;
        int256 pnl2 = leverageModProxy.getPositionSummary(tokenId2).profitLoss;

        assertEq(pnl1, 15e18, "PnL for position 1 is incorrect");
        assertEq(pnl2, 35e18, "PnL for position 2 is incorrect");

        skip(2 days);

        // Close first position
        announceAndExecuteLeverageClose({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        // Close second position
        announceAndExecuteLeverageClose({
            tokenId: tokenId2,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        // The amount received after closing the positions should be greater than margin deposited + profit from
        // price increase due to profits from funding payments.
        assertGt(
            WETH.balanceOf(alice),
            aliceBalanceBefore - stableDeposit + uint256(pnl1) + uint256(pnl2),
            "Alice should have profits after closing positions with price increase"
        );
    }

    function test_pnl_price_decrease() public {
        vm.startPrank(alice);

        uint256 aliceBalanceBefore = WETH.balanceOf(alice);
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });
        // 10 ETH collateral, 30 ETH additional size (4x leverage)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });
        // 70 ETH collateral, 70 ETH additional size (2x leverage)
        uint256 tokenId2 = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 70e18,
            additionalSize: 70e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // The price of ETH decreases by 20%.
        uint256 newCollateralPrice = 800e8;
        setWethPrice(newCollateralPrice);

        int256 pnl1 = leverageModProxy.getPositionSummary(tokenId).profitLoss;
        int256 pnl2 = leverageModProxy.getPositionSummary(tokenId2).profitLoss;

        assertEq(pnl1, -75e17, "PnL for position 1 is incorrect");
        assertEq(pnl2, -175e17, "PnL for position 2 is incorrect");

        skip(2 days);

        // Close first position
        announceAndExecuteLeverageClose({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        // Close second position
        announceAndExecuteLeverageClose({
            tokenId: tokenId2,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        uint256 keeperFee = mockKeeperFee.getKeeperFee();
        assertApproxEqRel(
            uint256(int256(aliceBalanceBefore) - int256(stableDeposit) - int256(keeperFee) + pnl1 + pnl2),
            WETH.balanceOf(alice),
            0.0000001e18, // looks like a rounding error
            "Alice should have losses after closing positions with price increase"
        );
    }

    function test_accrued_funding_long_skew_price_increase() public {
        vm.startPrank(alice);

        uint256 aliceBalanceBefore = WETH.balanceOf(alice);
        int256 stableDeposit = 100e18;
        int256 margin = 120e18;
        int256 additionalSize = 120e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: uint256(stableDeposit),
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });
        // 120 ETH collateral, 120 ETH additional size (2x leverage)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: uint256(margin),
            additionalSize: uint256(additionalSize),
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 keeperFee = mockKeeperFee.getKeeperFee();
        assertApproxEqRel(
            WETH.balanceOf(alice),
            aliceBalanceBefore - uint256(margin) - uint256(stableDeposit) - keeperFee,
            0.0000001e18 // looks like a rounding error
        ); // 100 deposit to stable LP, 120 deposit into 1 leveraged position

        // Mock WETH Chainlink price to $2k (100% increase)
        setWethPrice(2000e8);

        skip(2 days);

        // Leverage traders paid to the stable LPs.
        assertLt(leverageModProxy.getPositionSummary(tokenId).accruedFunding, 0, "Long trader gained funding fees");
        assertLt(
            leverageModProxy.fundingAdjustedLongPnLTotal(),
            leverageModProxy.getMarketSummary().profitLossTotalByLongs,
            "Longs gained funding fees"
        );
    }

    function test_accrued_funding_long_skew_price_decrease() public {
        vm.startPrank(alice);

        uint256 aliceBalanceBefore = WETH.balanceOf(alice);
        int256 stableDeposit = 100e18;
        int256 margin = 120e18;
        int256 additionalSize = 120e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: uint256(stableDeposit),
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });
        // 120 ETH collateral, 120 ETH additional size (2x leverage)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: uint256(margin),
            additionalSize: uint256(additionalSize),
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 keeperFee = mockKeeperFee.getKeeperFee();
        assertApproxEqRel(
            WETH.balanceOf(alice),
            aliceBalanceBefore - uint256(margin) - uint256(stableDeposit) - keeperFee,
            0.0000001e18 // looks like a rounding error
        ); // 100 deposit to stable LP, 120 deposit into 1 leveraged position

        // Mock WETH Chainlink price to $800 (20% decrease)
        setWethPrice(800e18);

        skip(2 days);

        // Leverage traders paid to the stable LPs due to skew towards the heavy side.
        assertLt(leverageModProxy.getPositionSummary(tokenId).accruedFunding, 0, "Long trader gained funding fees");
        assertLt(
            leverageModProxy.fundingAdjustedLongPnLTotal(),
            leverageModProxy.getMarketSummary().profitLossTotalByLongs,
            "Longs gained funding fees"
        );
    }

    function test_accrued_funding_stable_skew_price_increase() public {
        vm.startPrank(alice);

        uint256 aliceBalanceBefore = WETH.balanceOf(alice);
        int256 stableDeposit = 100e18;
        int256 margin = 40e18;
        int256 additionalSize = 40e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: uint256(stableDeposit),
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });
        // 40 ETH collateral, 40 ETH additional size (2x leverage)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: uint256(margin),
            additionalSize: uint256(additionalSize),
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 keeperFee = mockKeeperFee.getKeeperFee();
        assertApproxEqRel(
            WETH.balanceOf(alice),
            aliceBalanceBefore - uint256(margin) - uint256(stableDeposit) - keeperFee,
            0.0000001e18, // looks like a rounding error
            "Alice's balance incorrect"
        ); // 100 deposit to stable LP, 40 deposit into 1 leveraged position

        // Mock WETH Chainlink price to $2k (100% increase)
        setWethPrice(2000e8);

        skip(2 days);

        assertGt(leverageModProxy.getPositionSummary(tokenId).accruedFunding, 0, "Long trader gained funding fees");
        assertGt(
            leverageModProxy.fundingAdjustedLongPnLTotal(),
            leverageModProxy.getMarketSummary().profitLossTotalByLongs,
            "Longs gained funding fees"
        );
    }

    function test_accrued_funding_stable_skew_price_decrease() public {
        vm.startPrank(alice);

        uint256 aliceBalanceBefore = WETH.balanceOf(alice);
        int256 stableDeposit = 100e18;
        int256 margin = 40e18;
        int256 additionalSize = 40e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: uint256(stableDeposit),
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });
        // 40 ETH collateral, 40 ETH additional size (2x leverage)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: uint256(margin),
            additionalSize: uint256(additionalSize),
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 keeperFee = mockKeeperFee.getKeeperFee();
        assertApproxEqRel(
            WETH.balanceOf(alice),
            aliceBalanceBefore - uint256(margin) - uint256(stableDeposit) - keeperFee,
            0.0000001e18, // looks like a rounding error
            "Alice's balance incorrect"
        ); // 100 deposit to stable LP, 40 deposit into 1 leveraged position

        // Mock WETH Chainlink price to $800 (20% decrease)
        setWethPrice(800e8);

        skip(2 days);

        assertGt(leverageModProxy.getPositionSummary(tokenId).accruedFunding, 0, "Short trader gained funding fees");
        assertGt(
            leverageModProxy.fundingAdjustedLongPnLTotal(),
            leverageModProxy.getMarketSummary().profitLossTotalByLongs,
            "Shorts gained funding fees"
        );
    }

    function test_accounting_accrued_fees_for_stable_shares_long_skew() public {
        vm.startPrank(alice);

        uint256 aliceBalanceBefore = WETH.balanceOf(alice);
        int256 stableDeposit = 100e18;
        int256 margin = 120e18;
        int256 additionalSize = 120e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: uint256(stableDeposit),
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 aliceLiquidityMinted = stableModProxy.balanceOf(alice);

        // 120 ETH collateral, 120 ETH additional size (2x leverage)
        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: uint256(margin),
            additionalSize: uint256(additionalSize),
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 keeperFee = mockKeeperFee.getKeeperFee();
        assertApproxEqRel(
            WETH.balanceOf(alice),
            aliceBalanceBefore - uint256(margin) - uint256(stableDeposit) - keeperFee,
            0.0000001e18, // looks like a rounding error
            "Alice's balance incorrect"
        ); // 100 deposit to stable LP, 120 deposit into 1 leveraged position

        skip(2 days);

        announceAndExecuteDeposit({
            traderAccount: bob,
            keeperAccount: keeper,
            depositAmount: uint256(stableDeposit),
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 bobLiquidityMinted = stableModProxy.balanceOf(bob);

        // Since the market was skewed towards the long side, the stable LPs should have gained funding fees.
        // This means `stableCollaterPerShare` should be higher compared to the time Alice minted liquidity.
        // Since liquidity minted is inversely proportional to `stableCollateralPerShare`, Alice should have minted more liquidity than Bob.
        assertGt(aliceLiquidityMinted, bobLiquidityMinted, "Alice's liquidity minted should be greater than Bob's");
    }

    function test_accounting_accrued_fees_for_stable_shares_short_skew() public {
        vm.startPrank(alice);

        uint256 aliceBalanceBefore = WETH.balanceOf(alice);
        int256 stableDeposit = 100e18;
        int256 margin = 40e18;
        int256 additionalSize = 40e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: uint256(stableDeposit),
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 aliceLiquidityMinted = stableModProxy.balanceOf(alice);

        // 40 ETH collateral, 40 ETH additional size (2x leverage)
        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: uint256(margin),
            additionalSize: uint256(additionalSize),
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 keeperFee = mockKeeperFee.getKeeperFee();
        assertApproxEqRel(
            WETH.balanceOf(alice),
            aliceBalanceBefore - uint256(margin) - uint256(stableDeposit) - keeperFee,
            0.0000001e18, // looks like a rounding error
            "Alice's balance incorrect"
        ); // 100 deposit to stable LP, 40 deposit into 1 leveraged position

        skip(2 days);

        announceAndExecuteDeposit({
            traderAccount: bob,
            keeperAccount: keeper,
            depositAmount: uint256(stableDeposit),
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 bobLiquidityMinted = stableModProxy.balanceOf(bob);

        // Since the market was skewed towards the short side, the stable LPs should have lost funding fees.
        // This means `stableCollaterPerShare` should be lower compared to the time Alice minted liquidity.
        // Since liquidity minted is inversely proportional to `stableCollateralPerShare`, Alice should have minted less liquidity than Bob.
        assertLt(aliceLiquidityMinted, bobLiquidityMinted, "Alice's liquidity minted should be greater than Bob's");
    }

    // TODO: Revisit the test assertions.
    function test_current_funding_rate_when_market_prefectly_hedged() public {
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        // Creating a leverage position with leverage ratio 3x.
        // Note that this function creates a delta neutral position.
        announceAndExecuteDepositAndLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            margin: 50e18,
            additionalSize: 100e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        int256 currentFundingRateBefore = vaultProxy.getCurrentFundingRate();

        // The price of ETH increases by 100%.
        uint256 newCollateralPrice = 2000e8;
        setWethPrice(newCollateralPrice);

        skip(2 days);

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 1e6,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        skip(1 days);

        // The recomputed funding rate shouldn't be too different from the funding rate before the latest stable deposit.
        // We don't want big jumps happening due to small deposits.
        assertApproxEqAbs(
            vaultProxy.getCurrentFundingRate(),
            currentFundingRateBefore,
            1e6,
            "Funding rate shouldn't change"
        );
    }

    // This test does the following:
    // 1. Opens a hedged LP and leverage position with no skew
    // 2. Opens an additional leverage position to create positive skew (funding rates activated)
    // 3. Skips 1 day
    // 4. Checks accrued funding rate matches current funding rate
    // 5. Closes all positions and checks balances
    function test_funding_accrued() public {
        // Set funding velocity to 0 so that the funding rate is not affected in the beginning
        // this means that the funding will be 0 and skew will be 0 for the initial perfect hedge
        vm.startPrank(admin);
        vaultProxy.setMaxFundingVelocity(0);
        // Disable trading fees so that they don't impact the tests
        stableModProxy.setStableWithdrawFee(0);
        leverageModProxy.setLevTradingFee(0);

        vm.startPrank(alice);

        setWethPrice(2000e8);

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });

        uint256 tokenId1 = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 100e18,
            additionalSize: 100e18,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });

        // Skew = 0
        FlatcoinStructs.PositionSummary memory positionSummary = leverageModProxy.getPositionSummary(tokenId1);
        FlatcoinStructs.VaultSummary memory vaultSummary = vaultProxy.getVaultSummary();
        assertEq(vaultSummary.marketSkew, 0, "Market skew should be 0");
        assertEq(vaultProxy.getCurrentFundingRate(), 0, "Initial funding rate should be 0");
        assertEq(stableModProxy.stableCollateralPerShare(), 1e18, "Initial stable collateral per share should be 1e18");
        assertEq(positionSummary.accruedFunding, 0, "Initial position accrued funding should be 0");
        assertEq(positionSummary.profitLoss, 0, "Initial position profit loss should be 0");
        assertEq(
            positionSummary.marginAfterSettlement,
            100e18,
            "Initial position margin after settlement should be 100e18"
        );

        skip(1 days);

        // Nothing should change because skew = 0
        positionSummary = leverageModProxy.getPositionSummary(tokenId1);
        vaultSummary = vaultProxy.getVaultSummary();
        assertEq(vaultSummary.marketSkew, 0, "Market skew should be 0");
        assertEq(vaultProxy.getCurrentFundingRate(), 0, "Funding rate should be 0 after 1 day");
        assertEq(
            stableModProxy.stableCollateralPerShare(),
            1e18,
            "Stable collateral per share shouldn't change after 1 day"
        );
        assertEq(positionSummary.accruedFunding, 0, "Initial position accrued funding should be 0 after 1 day");
        assertEq(positionSummary.profitLoss, 0, "Initial position profit loss should be 0 after 1 day");
        assertEq(
            positionSummary.marginAfterSettlement,
            100e18,
            "Initial position margin after settlement should be 100e18 after 1 day"
        );

        // now that the system is perfectly hedged, let's check the funding math
        vm.prank(admin);
        vaultProxy.setMaxFundingVelocity(0.003e18); // 0.3% per day

        // Skew towards longs 10%
        uint256 tokenId2 = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 10e18,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });

        assertEq(vaultProxy.getCurrentFundingRate(), 0, "Incorrect funding rate immediately after skew change");
        vaultSummary = vaultProxy.getVaultSummary();
        assertEq(vaultSummary.marketSkew, 10e18, "Market skew should be 10e18 immediately after skew change");

        skip(1 days);
        vaultSummary = vaultProxy.getVaultSummary();
        assertEq(vaultSummary.marketSkew, 10e18, "Market skew should be 10e18 after 1 day skew");
        assertEq(vaultProxy.getCurrentFundingRate(), 0.003e18, "Incorrect funding rate after 1 day skew");
        positionSummary = leverageModProxy.getPositionSummary(tokenId2);
        assertEq(
            (positionSummary.accruedFunding * -1) / 10, // divide by the size
            vaultProxy.getCurrentFundingRate() / 2,
            "Incorrect accrued funding after 1 day skew"
        );
        uint256 traderWethBalanceBefore = WETH.balanceOf(alice);

        announceAndExecuteLeverageClose({
            tokenId: tokenId2,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });

        {
            int256 accruedFunding = positionSummary.accruedFunding;
            uint256 keeperFee = mockKeeperFee.getKeeperFee();

            assertApproxEqRel(
                (WETH.balanceOf(alice) - traderWethBalanceBefore), // check the returned balance to trader
                10e18 - // initial deposit
                    uint256(accruedFunding * -1) - // subtract the lost funding before the position closure
                    keeperFee - // subtract the keeper fee
                    (((vaultProxy.minExecutabilityAge() * 0.003e18) / 86_400) * 10), // subtract the additional lost funding after the delayed position closure
                0.0000002e18, // looks like a rounding error
                "Trader didn't get correct amount of WETH after close"
            );
        }

        announceAndExecuteLeverageClose({
            tokenId: tokenId1,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });

        announceAndExecuteWithdraw({
            traderAccount: alice,
            keeperAccount: keeper,
            withdrawAmount: stableModProxy.balanceOf(alice),
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });

        assertApproxEqAbs(
            WETH.balanceOf(alice),
            100_000e18 - 0.006e18, // account for 6 keeper fees of 0.001e18
            1e6,
            "Trader didn't get all her WETH back after closing everything"
        );
    }

    function test_funding_rate_unaffected_by_market_size() public {
        // The funding rate should only be affected by the skew, not total collateral market size
        vm.startPrank(admin);
        vaultProxy.setMaxFundingVelocity(0);
        // Disable trading fees so that they don't impact the tests
        stableModProxy.setStableWithdrawFee(0);
        leverageModProxy.setLevTradingFee(0);

        vm.startPrank(alice);

        setWethPrice(2000e8);

        uint256 snapshot = vm.snapshot();

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });

        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 100e18,
            additionalSize: 110e18,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });

        vm.prank(admin);
        vaultProxy.setMaxFundingVelocity(0.003e18); // 0.3% per day

        skip(1 days);

        FlatcoinStructs.VaultSummary memory vaultSummary = vaultProxy.getVaultSummary();
        assertEq(vaultSummary.marketSkew, 10e18, "Market should be skewed 10% long (initial market size)");
        assertEq(vaultProxy.getCurrentFundingRate(), 0.003e18, "Incorrect funding rate (initial market size)"); // 0.3% with 10% skew

        vm.revertTo(snapshot);

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 1000e18,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });

        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 1000e18,
            additionalSize: 1100e18,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });

        vm.startPrank(admin);
        vaultProxy.setMaxFundingVelocity(0.003e18);
        vaultProxy.setExecutabilityAge(1, 60); // minimum delay to keep the accrued funding close to being round and clean
        vm.startPrank(alice);

        skip(1 days);

        vaultSummary = vaultProxy.getVaultSummary();
        assertEq(vaultSummary.marketSkew, 100e18, "Market should be skewed 10% long (bigger market size)");
        assertEq(vaultProxy.getCurrentFundingRate(), 0.003e18, "Incorrect funding rate (bigger market size)");

        uint256 aliceWethBefore = WETH.balanceOf(alice);

        skip(1 days);

        // We can close the position to make sure nothing funny is going on with the funding rate
        announceAndExecuteLeverageClose({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });

        uint256 aliceWethReceived = WETH.balanceOf(alice) - aliceWethBefore;

        assertEq(vaultSummary.marketSkew, 100e18, "Market should be skewed 10% long (bigger market size)");
        assertApproxEqRel(
            vaultProxy.getCurrentFundingRate(),
            0.006e18,
            1e13,
            "Incorrect funding rate (bigger market size)"
        );
        assertApproxEqRel(
            aliceWethReceived,
            1000e18 -
                (1100 * 0.006e18) - // ~0.6% funding paid
                mockKeeperFee.getKeeperFee(),
            1e13,
            "Alice's WETH received is incorrect"
        );
    }

    // TODO: Change this test to use more assertions or else move it to a different test file.
    function test_funding_rate_skew_change() public {
        // The funding rate should only be affected by the skew, not total collateral market size
        vm.startPrank(admin);
        vaultProxy.setMaxFundingVelocity(0);
        // Disable trading fees so that they don't impact the tests
        stableModProxy.setStableWithdrawFee(0);
        leverageModProxy.setLevTradingFee(0);

        vm.startPrank(alice);

        setWethPrice(2000e8);

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });

        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 100e18,
            additionalSize: 120e18,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });

        vm.prank(admin);
        vaultProxy.setMaxFundingVelocity(0.003e18); // 0.3% per day

        int256 currentSkewBefore = vaultProxy.getCurrentSkew();
        int256 skewBefore = vaultProxy.getVaultSummary().marketSkew;
        int256 skewPercentageBefore = viewer.getMarketSkewPercentage();

        _expectRevertWithCustomError({
            target: address(this),
            callData: abi.encodeWithSelector(OrderHelpers.announceOpenLeverage.selector, alice, 0.1e18, 0.1e18, 0),
            expectedErrorSignature: "MaxSkewReached(uint256)",
            ignoreErrorArguments: true
        });

        assertEq(currentSkewBefore, skewBefore, "Current skew should be equal to market skew");

        skip(1 days);

        // Should be able to open a position because funding closes the skew
        {
            uint256 snapshot = vm.snapshot();
            announceOpenLeverage({traderAccount: alice, margin: 0.1e18, additionalSize: 0.1e18, keeperFeeAmount: 0});
            vm.revertTo(snapshot);
        }

        int256 currentSkewAfter = vaultProxy.getCurrentSkew();
        int256 skewAfter = vaultProxy.getVaultSummary().marketSkew;
        int256 skewPercentageAfter = viewer.getMarketSkewPercentage();

        assertLt(currentSkewAfter, currentSkewBefore, "Current skew should decrease over time");
        assertLt(skewPercentageAfter, skewPercentageBefore, "Skew percentage should decrease over time");
        assertLt(currentSkewAfter, skewAfter, "Current skew should be lower than market skew over time");

        vaultProxy.settleFundingFees();

        assertEq(
            currentSkewAfter,
            vaultProxy.getVaultSummary().marketSkew,
            "Market skew should be updated after settlement"
        );
    }
}
