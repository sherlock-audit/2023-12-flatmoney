// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";

import {ExpectRevert} from "../../helpers/ExpectRevert.sol";
import {OrderHelpers} from "../../helpers/OrderHelpers.sol";
import {FlatcoinErrors} from "../../../src/libraries/FlatcoinErrors.sol";
import {FlatcoinStructs} from "../../../src/libraries/FlatcoinStructs.sol";

import {IPyth} from "pyth-sdk-solidity/IPyth.sol";
import "src/interfaces/IChainlinkAggregatorV3.sol";

import "forge-std/console2.sol";

contract AdjustPositionInfluence is Setup, OrderHelpers {
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

    function test_adjustPosition_margin_addition_funding_rate_change_stable_skew() public {
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        announceOpenLeverage({traderAccount: bob, margin: 25e18, additionalSize: 50e18, keeperFeeAmount: 0});

        announceOpenLeverage({traderAccount: carol, margin: 25e18, additionalSize: 35e18, keeperFeeAmount: 0});

        skip(uint256(vaultProxy.minExecutabilityAge())); // must reach minimum executability time

        uint256 tokenId = executeOpenLeverage({
            traderAccount: bob,
            keeperAccount: keeper,
            oraclePrice: collateralPrice
        });

        uint256 tokenId2 = executeOpenLeverage({
            traderAccount: carol,
            keeperAccount: keeper,
            oraclePrice: collateralPrice
        });

        skip(1 days);

        int256 fundingRateBefore = vaultProxy.getCurrentFundingRate();

        // +5 ETH margin of position 2, no change in position size.
        announceAdjustLeverage({
            tokenId: tokenId2,
            traderAccount: carol,
            marginAdjustment: 5e18,
            additionalSizeAdjustment: 0,
            keeperFeeAmount: 0
        });

        skip(uint256(vaultProxy.minExecutabilityAge())); // must reach minimum executability time

        FlatcoinStructs.PositionSummary memory positionSummaryBefore1 = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore2 = leverageModProxy.getPositionSummary(tokenId2);

        executeAdjustLeverage({keeperAccount: keeper, traderAccount: carol, oraclePrice: collateralPrice});

        skip(2 days);

        int256 fundingRateAfter = vaultProxy.getCurrentFundingRate();
        FlatcoinStructs.PositionSummary memory positionSummaryAfter1 = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryAfter2 = leverageModProxy.getPositionSummary(tokenId2);

        assertEq(
            vaultProxy.getPosition(tokenId2).marginDeposited,
            uint256(positionSummaryBefore2.marginAfterSettlement + 5e18),
            "Margin incorrect after adjustment"
        );

        // Because the market is still stable skewed, the funding rate should decrease thus favouring the longs.
        assertLt(fundingRateAfter, fundingRateBefore, "Funding rate should still decrease after adjustment");

        assertGt(
            positionSummaryBefore1.accruedFunding,
            positionSummaryBefore2.accruedFunding,
            "Position 1 should have earned more funding fees before margin adjustment for position 2"
        );
        assertGt(
            positionSummaryAfter1.accruedFunding - positionSummaryBefore1.accruedFunding,
            positionSummaryAfter2.accruedFunding - positionSummaryBefore2.accruedFunding,
            "Position 1 should have earned more funding fees after margin adjustment for position 2"
        );
    }

    function test_adjustPosition_margin_addition_funding_rate_change_long_skew() public {
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        announceOpenLeverage({traderAccount: bob, margin: 25e18, additionalSize: 55e18, keeperFeeAmount: 0});

        announceOpenLeverage({traderAccount: carol, margin: 25e18, additionalSize: 50e18, keeperFeeAmount: 0});

        skip(uint256(vaultProxy.minExecutabilityAge())); // must reach minimum executability time

        uint256 tokenId = executeOpenLeverage({
            traderAccount: bob,
            keeperAccount: keeper,
            oraclePrice: collateralPrice
        });

        uint256 tokenId2 = executeOpenLeverage({
            traderAccount: carol,
            keeperAccount: keeper,
            oraclePrice: collateralPrice
        });

        skip(1 days);

        int256 fundingRateBefore = vaultProxy.getCurrentFundingRate();

        // +5 ETH margin of position 2, no change in position size.
        announceAdjustLeverage({
            tokenId: tokenId2,
            traderAccount: carol,
            marginAdjustment: 5e18,
            additionalSizeAdjustment: 0,
            keeperFeeAmount: 0
        });

        skip(uint256(vaultProxy.minExecutabilityAge())); // must reach minimum executability time

        FlatcoinStructs.PositionSummary memory positionSummaryBefore1 = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore2 = leverageModProxy.getPositionSummary(tokenId2);

        executeAdjustLeverage({keeperAccount: keeper, traderAccount: carol, oraclePrice: collateralPrice});

        skip(2 days);

        int256 fundingRateAfter = vaultProxy.getCurrentFundingRate();
        FlatcoinStructs.PositionSummary memory positionSummaryAfter1 = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryAfter2 = leverageModProxy.getPositionSummary(tokenId2);

        assertEq(
            vaultProxy.getPosition(tokenId2).marginDeposited,
            uint256(positionSummaryBefore2.marginAfterSettlement + 5e18),
            "Margin incorrect after adjustment"
        );

        // Because the market is still long skewed, the funding rate should increase thus favouring the stable LPs.
        assertGt(fundingRateAfter, fundingRateBefore, "Funding rate should still decrease after adjustment");
        assertLt(
            positionSummaryBefore1.accruedFunding,
            positionSummaryBefore2.accruedFunding,
            "Position 1 should have paid more funding fees before margin adjustment for position 2"
        );
        assertLt(
            positionSummaryAfter1.accruedFunding - positionSummaryBefore1.accruedFunding,
            positionSummaryAfter2.accruedFunding - positionSummaryBefore2.accruedFunding,
            "Position 1 should have paid more funding fees after margin adjustment for position 2"
        );
    }

    function test_adjustPosition_margin_reduction_funding_rate_change_stable_skew() public {
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        announceOpenLeverage({traderAccount: bob, margin: 25e18, additionalSize: 50e18, keeperFeeAmount: 0});

        announceOpenLeverage({traderAccount: carol, margin: 25e18, additionalSize: 35e18, keeperFeeAmount: 0});

        skip(uint256(vaultProxy.minExecutabilityAge())); // must reach minimum executability time

        uint256 tokenId = executeOpenLeverage({
            traderAccount: bob,
            keeperAccount: keeper,
            oraclePrice: collateralPrice
        });

        uint256 tokenId2 = executeOpenLeverage({
            traderAccount: carol,
            keeperAccount: keeper,
            oraclePrice: collateralPrice
        });

        skip(1 days);

        int256 fundingRateBefore = vaultProxy.getCurrentFundingRate();

        // -5 ETH margin of position 2, no change in position size.
        announceAdjustLeverage({
            tokenId: tokenId2,
            traderAccount: carol,
            marginAdjustment: -5e18,
            additionalSizeAdjustment: 0,
            keeperFeeAmount: 0
        });

        skip(uint256(vaultProxy.minExecutabilityAge())); // must reach minimum executability time

        FlatcoinStructs.PositionSummary memory positionSummaryBefore1 = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore2 = leverageModProxy.getPositionSummary(tokenId2);

        executeAdjustLeverage({keeperAccount: keeper, traderAccount: carol, oraclePrice: collateralPrice});

        skip(2 days);

        int256 fundingRateAfter = vaultProxy.getCurrentFundingRate();
        FlatcoinStructs.PositionSummary memory positionSummaryAfter1 = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryAfter2 = leverageModProxy.getPositionSummary(tokenId2);

        // When reducing the margin, the keeper fee is taken from the margin itself.
        assertEq(
            vaultProxy.getPosition(tokenId2).marginDeposited,
            uint256(positionSummaryBefore2.marginAfterSettlement - 5e18 - int256(mockKeeperFee.getKeeperFee())),
            "Margin incorrect after adjustment"
        );

        // Because the market is still stable skewed, the funding rate should decrease thus favouring the longs.
        assertLt(fundingRateAfter, fundingRateBefore, "Funding rate should still decrease after adjustment");

        assertGt(
            positionSummaryBefore1.accruedFunding,
            positionSummaryBefore2.accruedFunding,
            "Position 1 should have earned more funding fees before margin adjustment for position 2"
        );
        assertGt(
            positionSummaryAfter1.accruedFunding - positionSummaryBefore1.accruedFunding,
            positionSummaryAfter2.accruedFunding - positionSummaryBefore2.accruedFunding,
            "Position 1 should have earned more funding fees after margin adjustment for position 2"
        );
    }

    function test_adjustPosition_margin_reduction_funding_rate_change_long_skew() public {
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        announceOpenLeverage({traderAccount: bob, margin: 25e18, additionalSize: 55e18, keeperFeeAmount: 0});

        announceOpenLeverage({traderAccount: carol, margin: 25e18, additionalSize: 50e18, keeperFeeAmount: 0});

        skip(uint256(vaultProxy.minExecutabilityAge())); // must reach minimum executability time

        uint256 tokenId = executeOpenLeverage({
            traderAccount: bob,
            keeperAccount: keeper,
            oraclePrice: collateralPrice
        });

        uint256 tokenId2 = executeOpenLeverage({
            traderAccount: carol,
            keeperAccount: keeper,
            oraclePrice: collateralPrice
        });

        skip(1 days);

        int256 fundingRateBefore = vaultProxy.getCurrentFundingRate();

        // -5 ETH margin of position 2, no change in position size.
        announceAdjustLeverage({
            tokenId: tokenId2,
            traderAccount: carol,
            marginAdjustment: -5e18,
            additionalSizeAdjustment: 0,
            keeperFeeAmount: 0
        });

        skip(uint256(vaultProxy.minExecutabilityAge())); // must reach minimum executability time

        FlatcoinStructs.PositionSummary memory positionSummaryBefore1 = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore2 = leverageModProxy.getPositionSummary(tokenId2);

        executeAdjustLeverage({keeperAccount: keeper, traderAccount: carol, oraclePrice: collateralPrice});

        skip(2 days);

        int256 fundingRateAfter = vaultProxy.getCurrentFundingRate();
        FlatcoinStructs.PositionSummary memory positionSummaryAfter1 = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryAfter2 = leverageModProxy.getPositionSummary(tokenId2);

        // When reducing the margin, the keeper fee is taken from the margin itself.
        assertEq(
            vaultProxy.getPosition(tokenId2).marginDeposited,
            uint256(positionSummaryBefore2.marginAfterSettlement - 5e18 - int256(mockKeeperFee.getKeeperFee())),
            "Margin incorrect after adjustment"
        );

        // Because the market is still long skewed, the funding rate should increase thus favouring the stable LPs.
        assertGt(fundingRateAfter, fundingRateBefore, "Funding rate should still decrease after adjustment");
        assertLt(
            positionSummaryBefore1.accruedFunding,
            positionSummaryBefore2.accruedFunding,
            "Position 1 should have paid more funding fees before margin adjustment for position 2"
        );
        assertLt(
            positionSummaryAfter1.accruedFunding - positionSummaryBefore1.accruedFunding,
            positionSummaryAfter2.accruedFunding - positionSummaryBefore2.accruedFunding,
            "Position 1 should have paid more funding fees after margin adjustment for position 2"
        );
    }

    // This test checks that the funding fees accrued by two positions with the same position size at the end of a period
    // but one adjusted with position size addition and the other staying the same, don't earn the same amount of funding fees.
    //      Position 1 => 50 ETH position size from the beginning.
    //      Position 2 => 25 ETH in the beginning, then 25 ETH added.
    function test_adjustPosition_size_addition_funding_fees_accrued_when_two_positions_end_with_the_same_position_size_stable_skew()
        public
    {
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        announceOpenLeverage({traderAccount: bob, margin: 25e18, additionalSize: 50e18, keeperFeeAmount: 0});

        announceOpenLeverage({traderAccount: carol, margin: 25e18, additionalSize: 25e18, keeperFeeAmount: 0});

        skip(uint256(vaultProxy.minExecutabilityAge())); // must reach minimum executability time

        uint256 tokenId = executeOpenLeverage({
            traderAccount: bob,
            keeperAccount: keeper,
            oraclePrice: collateralPrice
        });

        uint256 tokenId2 = executeOpenLeverage({
            traderAccount: carol,
            keeperAccount: keeper,
            oraclePrice: collateralPrice
        });

        skip(1 days);

        // int256 fundingRateBefore = vaultProxy.getCurrentFundingRate();

        // +25 ETH position size of position 2, no change in margin.
        announceAdjustLeverage({
            tokenId: tokenId2,
            traderAccount: carol,
            marginAdjustment: 0,
            additionalSizeAdjustment: 25e18,
            keeperFeeAmount: 0
        });

        skip(uint256(vaultProxy.minExecutabilityAge())); // must reach minimum executability time

        FlatcoinStructs.PositionSummary memory positionSummaryBefore1 = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore2 = leverageModProxy.getPositionSummary(tokenId2);

        uint256 tradeFee = executeAdjustLeverage({
            keeperAccount: keeper,
            traderAccount: carol,
            oraclePrice: collateralPrice
        });

        skip(2 days);

        // int256 fundingRateAfter = vaultProxy.getCurrentFundingRate();
        FlatcoinStructs.PositionSummary memory positionSummaryAfter1 = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryAfter2 = leverageModProxy.getPositionSummary(tokenId2);

        assertEq(
            vaultProxy.getPosition(tokenId2).marginDeposited,
            uint256(
                positionSummaryBefore2.marginAfterSettlement - int256(tradeFee) - int256(mockKeeperFee.getKeeperFee())
            ),
            "Margin incorrect after adjustment"
        );
        assertGt(
            positionSummaryBefore1.accruedFunding,
            positionSummaryBefore2.accruedFunding,
            "Position 1 should have earned more funding fees before size adjustment of position 2"
        );

        // When adjusting position 2, accrued funding was settled.
        assertApproxEqAbs(
            positionSummaryAfter1.accruedFunding - positionSummaryBefore1.accruedFunding,
            positionSummaryAfter2.accruedFunding,
            1e6, // Rounding error only.
            "Both should have earned the same amount of funding fees after size adjustment of position 2"
        );
    }

    // This test checks that the funding fees accrued by two positions with the same position size at the end of a period
    // but one adjusted with position size addition and the other staying the same, don't earn the same amount of funding fees.
    //      Position 1 => 55 ETH position size from the beginning.
    //      Position 2 => 50 ETH in the beginning, then 5 ETH added.
    function test_adjustPosition_size_addition_funding_fees_accrued_when_two_positions_end_with_the_same_position_size_long_skew()
        public
    {
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        announceOpenLeverage({traderAccount: bob, margin: 25e18, additionalSize: 55e18, keeperFeeAmount: 0});

        announceOpenLeverage({traderAccount: carol, margin: 25e18, additionalSize: 50e18, keeperFeeAmount: 0});

        skip(uint256(vaultProxy.minExecutabilityAge())); // must reach minimum executability time

        uint256 tokenId = executeOpenLeverage({
            traderAccount: bob,
            keeperAccount: keeper,
            oraclePrice: collateralPrice
        });

        uint256 tokenId2 = executeOpenLeverage({
            traderAccount: carol,
            keeperAccount: keeper,
            oraclePrice: collateralPrice
        });

        skip(1 days);

        // +25 ETH position size of position 2, no change in margin.
        announceAdjustLeverage({
            tokenId: tokenId2,
            traderAccount: carol,
            marginAdjustment: 0,
            additionalSizeAdjustment: 5e18,
            keeperFeeAmount: 0
        });

        skip(uint256(vaultProxy.minExecutabilityAge())); // must reach minimum executability time

        FlatcoinStructs.PositionSummary memory positionSummaryBefore1 = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore2 = leverageModProxy.getPositionSummary(tokenId2);

        uint256 tradeFee = executeAdjustLeverage({
            keeperAccount: keeper,
            traderAccount: carol,
            oraclePrice: collateralPrice
        });

        skip(2 days);

        FlatcoinStructs.PositionSummary memory positionSummaryAfter1 = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryAfter2 = leverageModProxy.getPositionSummary(tokenId2);

        assertEq(
            vaultProxy.getPosition(tokenId2).marginDeposited,
            uint256(
                positionSummaryBefore2.marginAfterSettlement - int256(tradeFee) - int256(mockKeeperFee.getKeeperFee())
            ),
            "Margin incorrect after adjustment"
        );
        assertLt(
            positionSummaryBefore1.accruedFunding,
            positionSummaryBefore2.accruedFunding,
            "Position 1 should have paid more funding fees before size adjustment of position 2"
        );
        assertApproxEqAbs(
            positionSummaryAfter1.accruedFunding - positionSummaryBefore1.accruedFunding,
            positionSummaryAfter2.accruedFunding,
            1e6, //Rounding error only.
            "Both should have paid the same amount of funding fees after size adjustment of position 2"
        );
    }

    // This test checks that the funding fees accrued by two positions with the same position size at the end of a period
    // but one adjusted with position size reduction and the other staying the same, don't earn the same amount of funding fees.
    //      Position 1 => 25 ETH position size from the beginning.
    //      Position 2 => 50 ETH in the beginning, then 25 ETH reduced.
    function test_adjustPosition_size_reduction_funding_fees_accrued_when_two_positions_end_with_the_same_position_size_stable_skew()
        public
    {
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        announceOpenLeverage({traderAccount: bob, margin: 25e18, additionalSize: 25e18, keeperFeeAmount: 0});

        announceOpenLeverage({traderAccount: carol, margin: 25e18, additionalSize: 50e18, keeperFeeAmount: 0});

        skip(uint256(vaultProxy.minExecutabilityAge())); // must reach minimum executability time

        uint256 tokenId = executeOpenLeverage({
            traderAccount: bob,
            keeperAccount: keeper,
            oraclePrice: collateralPrice
        });

        uint256 tokenId2 = executeOpenLeverage({
            traderAccount: carol,
            keeperAccount: keeper,
            oraclePrice: collateralPrice
        });

        skip(1 days);

        // int256 fundingRateBefore = vaultProxy.getCurrentFundingRate();

        // +25 ETH position size of position 2, no change in margin.
        announceAdjustLeverage({
            tokenId: tokenId2,
            traderAccount: carol,
            marginAdjustment: 0,
            additionalSizeAdjustment: -25e18,
            keeperFeeAmount: 0
        });

        skip(uint256(vaultProxy.minExecutabilityAge())); // must reach minimum executability time

        FlatcoinStructs.PositionSummary memory positionSummaryBefore1 = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore2 = leverageModProxy.getPositionSummary(tokenId2);

        uint256 tradeFee = executeAdjustLeverage({
            keeperAccount: keeper,
            traderAccount: carol,
            oraclePrice: collateralPrice
        });

        skip(2 days);

        // int256 fundingRateAfter = vaultProxy.getCurrentFundingRate();
        FlatcoinStructs.PositionSummary memory positionSummaryAfter1 = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryAfter2 = leverageModProxy.getPositionSummary(tokenId2);

        assertEq(
            vaultProxy.getPosition(tokenId2).marginDeposited,
            uint256(
                positionSummaryBefore2.marginAfterSettlement - int256(tradeFee) - int256(mockKeeperFee.getKeeperFee())
            ),
            "Margin incorrect after adjustment"
        );
        assertLt(
            positionSummaryBefore1.accruedFunding,
            positionSummaryBefore2.accruedFunding,
            "Position 1 should have earned lesser funding fees before size adjustment of position 2"
        );
        assertApproxEqAbs(
            positionSummaryAfter1.accruedFunding - positionSummaryBefore1.accruedFunding,
            positionSummaryAfter2.accruedFunding,
            1e6, // Rounding error only.
            "Both should have earned the same amount of funding fees after adjustment"
        );
    }

    // This test checks that the funding fees accrued by two positions with the same position size at the end of a period
    // but one adjusted with position size reduction and the other staying the same, don't earn the same amount of funding fees.
    //      Position 1 => 25 ETH position size from the beginning.
    //      Position 2 => 50 ETH in the beginning, then 25 ETH reduced.
    function test_adjustPosition_size_reduction_funding_fees_accrued_when_two_positions_end_with_the_same_position_size_long_skew()
        public
    {
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        announceOpenLeverage({traderAccount: bob, margin: 25e18, additionalSize: 55e18, keeperFeeAmount: 0});

        announceOpenLeverage({traderAccount: carol, margin: 25e18, additionalSize: 60e18, keeperFeeAmount: 0});

        skip(uint256(vaultProxy.minExecutabilityAge())); // must reach minimum executability time

        uint256 tokenId = executeOpenLeverage({
            traderAccount: bob,
            keeperAccount: keeper,
            oraclePrice: collateralPrice
        });

        uint256 tokenId2 = executeOpenLeverage({
            traderAccount: carol,
            keeperAccount: keeper,
            oraclePrice: collateralPrice
        });

        skip(1 days);

        // int256 fundingRateBefore = vaultProxy.getCurrentFundingRate();

        // +25 ETH position size of position 2, no change in margin.
        announceAdjustLeverage({
            tokenId: tokenId2,
            traderAccount: carol,
            marginAdjustment: 0,
            additionalSizeAdjustment: -5e18,
            keeperFeeAmount: 0
        });

        skip(uint256(vaultProxy.minExecutabilityAge())); // must reach minimum executability time

        FlatcoinStructs.PositionSummary memory positionSummaryBefore1 = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore2 = leverageModProxy.getPositionSummary(tokenId2);

        uint256 tradeFee = executeAdjustLeverage({
            keeperAccount: keeper,
            traderAccount: carol,
            oraclePrice: collateralPrice
        });

        skip(2 days);

        // int256 fundingRateAfter = vaultProxy.getCurrentFundingRate();
        FlatcoinStructs.PositionSummary memory positionSummaryAfter1 = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryAfter2 = leverageModProxy.getPositionSummary(tokenId2);

        assertEq(
            vaultProxy.getPosition(tokenId2).marginDeposited,
            uint256(
                positionSummaryBefore2.marginAfterSettlement - int256(tradeFee) - int256(mockKeeperFee.getKeeperFee())
            ),
            "Margin incorrect after adjustment"
        );
        assertGt(
            positionSummaryBefore1.accruedFunding,
            positionSummaryBefore2.accruedFunding,
            "Position 2 should have paid more funding fees before its size adjustment"
        );
        assertApproxEqAbs(
            positionSummaryAfter1.accruedFunding - positionSummaryBefore1.accruedFunding,
            positionSummaryAfter2.accruedFunding,
            1e6, // Rounding error only.
            "Both should have paid the same amount of funding fees after adjustment"
        );
    }
}
