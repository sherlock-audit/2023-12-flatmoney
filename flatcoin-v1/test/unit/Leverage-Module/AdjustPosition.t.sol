// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {ExpectRevert} from "../../helpers/ExpectRevert.sol";
import {OrderHelpers} from "../../helpers/OrderHelpers.sol";
import {FlatcoinErrors} from "../../../src/libraries/FlatcoinErrors.sol";
import {FlatcoinStructs} from "../../../src/libraries/FlatcoinStructs.sol";

import "forge-std/console2.sol";

contract AdjustPositionTest is OrderHelpers, ExpectRevert {
    uint256 leverageTradingFee = 0.001e18; // 0.1%

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);

        leverageModProxy.setLevTradingFee(leverageTradingFee);
    }

    /**
     * Reverts
     */
    function test_revert_adjust_position_when_leverage_too_small() public {
        vm.startPrank(alice);

        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // 10 ETH margin, 30 ETH size (4x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // -26 ETH size, no change in margin
        _expectRevertWithCustomError({
            target: address(this),
            callData: abi.encodeWithSelector(
                OrderHelpers.announceAndExecuteLeverageAdjust.selector,
                tokenId,
                alice,
                keeper,
                0,
                -26e18,
                collateralPrice,
                0
            ),
            errorData: abi.encodeWithSelector(
                FlatcoinErrors.LeverageTooLow.selector,
                1.5e18,
                1e18 + (4e18 * 1e18) / (10e18 - leverageModProxy.getTradeFee(26e18) - mockKeeperFee.getKeeperFee())
            )
        });
    }

    function test_revert_adjust_position_when_caller_not_position_owner() public {
        vm.startPrank(alice);

        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // 10 ETH margin, 30 ETH size (4x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // +10 ETH margin, no change in size
        _expectRevertWithCustomError({
            target: address(this),
            callData: abi.encodeWithSelector(
                OrderHelpers.announceAndExecuteLeverageAdjust.selector,
                tokenId,
                bob,
                keeper,
                10e18,
                0,
                collateralPrice,
                0
            ),
            errorData: abi.encodeWithSelector(FlatcoinErrors.NotTokenOwner.selector, tokenId, bob)
        });
    }

    function test_revert_adjust_position_when_adjustments_not_specified() public {
        vm.startPrank(alice);

        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // 10 ETH margin, 30 ETH size (4x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // no change in margin, no change in size
        _expectRevertWithCustomError({
            target: address(this),
            callData: abi.encodeWithSelector(
                OrderHelpers.announceAndExecuteLeverageAdjust.selector,
                tokenId,
                alice,
                keeper,
                0,
                0,
                collateralPrice,
                0
            ),
            errorData: abi.encodeWithSelector(
                FlatcoinErrors.ZeroValue.selector,
                "marginAdjustment|additionalSizeAdjustment"
            )
        });
    }

    function test_revert_adjust_position_when_withdrawing_more_margin_then_exists() public {
        vm.startPrank(alice);

        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // 10 ETH margin, 30 ETH size (4x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // -20 ETH margin, no change in size
        _expectRevertWithCustomError({
            target: address(this),
            callData: abi.encodeWithSelector(
                OrderHelpers.announceAndExecuteLeverageAdjust.selector,
                tokenId,
                alice,
                keeper,
                -20e18,
                0,
                collateralPrice,
                0
            ),
            errorData: abi.encodeWithSelector(FlatcoinErrors.ValueNotPositive.selector, "newMargin|newAdditionalSize")
        });
    }

    function test_revert_adjust_position_when_adjusted_position_creates_bad_debt() public {
        vm.startPrank(alice);

        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // 10 ETH margin, 30 ETH size (4x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        vm.startPrank(admin);

        // Effectively remove the max leverage limit so that a position can be immediately liquidatable.
        // Immediately liquidatable due to liquidation buffer/margin provided being less than required
        // for the position size.
        leverageModProxy.setLeverageCriteria({
            _marginMin: 0.05e18,
            _leverageMin: 1.5e18,
            _leverageMax: type(uint256).max
        });

        // Modifying the position to have margin as 0.05 ETH and additional size as 120 ETH
        // effectively creating a position with lesser margin than required for as liquidation margin.
        _expectRevertWithCustomError({
            target: address(this),
            callData: abi.encodeWithSelector(
                OrderHelpers.announceAdjustLeverage.selector,
                alice,
                tokenId,
                int256(-9.95e18) + int256(leverageModProxy.getTradeFee(90e18)) + int256(mockKeeperFee.getKeeperFee()),
                90e18,
                0
            ),
            errorData: FlatcoinErrors.PositionCreatesBadDebt.selector,
            ignoreErrorArguments: true
        });
    }

    function test_revert_adjust_position_when_minimum_margin_not_satisfied() public {
        vm.startPrank(alice);

        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // 10 ETH margin, 30 ETH size (4x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        vm.startPrank(admin);

        // Effectively remove the max leverage limit so that a position can be immediately liquidatable.
        // Immediately liquidatable due to liquidation buffer/margin provided being less than required
        // for the position size.
        // Also increase the minimum margin requirement to 0.075 ETH so that the min margin assertion check
        // in the adjust function fails.
        leverageModProxy.setLeverageCriteria({
            _marginMin: 0.075e18,
            _leverageMin: 1.5e18,
            _leverageMax: type(uint256).max
        });

        // Modifying the position to have margin as 0.05 ETH and additional size as 120 ETH
        // effectively creating a position with lesser margin than required for as liquidation margin.
        _expectRevertWithCustomError({
            target: address(this),
            callData: abi.encodeWithSelector(
                OrderHelpers.announceAdjustLeverage.selector,
                alice,
                tokenId,
                int256(-9.95e18) + int256(leverageModProxy.getTradeFee(90e18)) + int256(mockKeeperFee.getKeeperFee()),
                90e18,
                0
            ),
            errorData: abi.encodeWithSelector(FlatcoinErrors.MarginTooSmall.selector, 0.075e18, 0.05e18)
        });
    }

    function test_revert_adjust_position_when_current_margin_not_enough_to_cover_fees() public {
        vm.startPrank(alice);

        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // 10 ETH margin, 30 ETH size (4x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // -10 ETH margin, -10 ETH in size
        _expectRevertWithCustomError({
            target: address(this),
            callData: abi.encodeWithSelector(
                OrderHelpers.announceAndExecuteLeverageAdjust.selector,
                tokenId,
                alice,
                keeper,
                -10e18,
                -10e18,
                collateralPrice,
                0
            ),
            errorData: abi.encodeWithSelector(FlatcoinErrors.ValueNotPositive.selector, "newMargin|newAdditionalSize")
        });
    }

    /**
     * Price Increase Suites (8 Scenarios)
     */
    function test_adjust_position_margin_increase_price_increase() public {
        vm.startPrank(alice);

        uint256 aliceCollateralBalanceBefore = WETH.balanceOf(alice);
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // 10 ETH margin, 30 ETH size (4x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 newCollateralPrice = 2000e8;
        // 100% increase
        setWethPrice(newCollateralPrice);

        FlatcoinStructs.Position memory positionBefore = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummaryBefore = leverageModProxy.getMarketSummary();
        uint256 collateralPerShareBefore = stableModProxy.stableCollateralPerShare();

        // +5 ETH margin, no change in size
        uint256 adjustmentTradeFee = announceAndExecuteLeverageAdjust({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            marginAdjustment: 5e18,
            additionalSizeAdjustment: 0,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        assertEq(adjustmentTradeFee, 0, "Trade fee should be 0 as no size was adjusted");
        // Trade fee is not taken (0) when size is not adjusted
        assertEq(
            aliceCollateralBalanceBefore -
                mockKeeperFee.getKeeperFee() *
                3 -
                leverageModProxy.getTradeFee(30e18) -
                stableDeposit -
                15e18,
            WETH.balanceOf(alice),
            "Alice collateral balance incorrect"
        );

        FlatcoinStructs.Position memory position = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummary = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummary = leverageModProxy.getMarketSummary();
        uint256 collateralPerShare = stableModProxy.stableCollateralPerShare();

        assertEq(
            position.entryPrice,
            1000e18,
            "Entry price should match price during open, as no additional size was added"
        );
        assertEq(
            position.marginDeposited,
            positionBefore.marginDeposited + 5e18,
            "Margin is not correct after adjustment"
        );
        assertEq(position.additionalSize, positionBefore.additionalSize, "Size is not correct after adjustment");
        assertEq(positionSummary.profitLoss, positionSummaryBefore.profitLoss, "PnL is not correct after adjustment");
        assertEq(
            marketSummary.profitLossTotalByLongs,
            marketSummaryBefore.profitLossTotalByLongs,
            "Total PnL is not correct after adjustment"
        );
        assertEq(
            collateralPerShare,
            collateralPerShareBefore,
            "Collateral per share should not change after adjustment"
        );
    }

    function test_adjust_position_size_increase_price_increase() public {
        vm.startPrank(alice);

        uint256 aliceCollateralBalanceBefore = WETH.balanceOf(alice);
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // 10 ETH margin, 30 ETH size (4x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 newCollateralPrice = 2000e8;
        // 100% increase
        setWethPrice(newCollateralPrice);

        FlatcoinStructs.Position memory positionBefore = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummaryBefore = leverageModProxy.getMarketSummary();
        uint256 collateralPerShareBefore = stableModProxy.stableCollateralPerShare();

        // +10 ETH size, no change in margin
        uint256 adjustmentTradeFee = announceAndExecuteLeverageAdjust({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            marginAdjustment: 0,
            additionalSizeAdjustment: 10e18,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        // Trade fee is taken from existing margin during size adjustments when margin adjustment = 0
        assertEq(
            aliceCollateralBalanceBefore -
                mockKeeperFee.getKeeperFee() *
                2 -
                leverageModProxy.getTradeFee(30e18) -
                stableDeposit -
                10e18,
            WETH.balanceOf(alice),
            "Alice collateral balance incorrect"
        );

        FlatcoinStructs.Position memory position = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummary = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummary = leverageModProxy.getMarketSummary();
        uint256 collateralPerShare = stableModProxy.stableCollateralPerShare();

        // Entry price should be 1250e18, as 10 ETH was added to the position.
        // This is because, the new average price is => [(1000 * 30) + (2000 * 10)] / 40 = 1250.
        assertEq(position.entryPrice, 1250e18, "Entry price is not correct after adjustment");
        assertEq(
            position.marginDeposited,
            positionBefore.marginDeposited - mockKeeperFee.getKeeperFee() - adjustmentTradeFee,
            "Margin is not correct after adjustment"
        );
        assertEq(
            position.additionalSize,
            positionBefore.additionalSize + 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(positionSummary.profitLoss, positionSummaryBefore.profitLoss, "PnL is not correct after adjustment");
        assertEq(
            marketSummary.profitLossTotalByLongs,
            marketSummaryBefore.profitLossTotalByLongs,
            "Total PnL is not correct after adjustment"
        );
        assertGt(
            collateralPerShare,
            collateralPerShareBefore,
            "Collateral per share should increase after adjustment because of trade fee"
        );
    }

    function test_adjust_position_margin_increase_size_increase_price_increase() public {
        vm.startPrank(alice);

        uint256 aliceCollateralBalanceBefore = WETH.balanceOf(alice);
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // 10 ETH margin, 30 ETH size (4x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 newCollateralPrice = 2000e8;
        // 100% increase
        setWethPrice(newCollateralPrice);

        FlatcoinStructs.Position memory positionBefore = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummaryBefore = leverageModProxy.getMarketSummary();
        uint256 collateralPerShareBefore = stableModProxy.stableCollateralPerShare();

        // +10 ETH margin, +10 ETH size
        uint256 adjustmentTradeFee = announceAndExecuteLeverageAdjust({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            marginAdjustment: 10e18,
            additionalSizeAdjustment: 10e18,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        // Trade fee is taken from user during size adjustments when margin adjustment >= 0
        assertEq(
            aliceCollateralBalanceBefore -
                mockKeeperFee.getKeeperFee() *
                3 -
                leverageModProxy.getTradeFee(30e18) -
                stableDeposit -
                20e18 -
                adjustmentTradeFee,
            WETH.balanceOf(alice),
            "Alice collateral balance incorrect"
        );

        FlatcoinStructs.Position memory position = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummary = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummary = leverageModProxy.getMarketSummary();
        uint256 collateralPerShare = stableModProxy.stableCollateralPerShare();

        assertEq(position.entryPrice, 1250e18, "Entry price is not correct after adjustment");
        assertEq(
            position.marginDeposited,
            positionBefore.marginDeposited + 10e18,
            "Margin is not correct after adjustment"
        );
        assertEq(
            position.additionalSize,
            positionBefore.additionalSize + 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(positionSummary.profitLoss, positionSummaryBefore.profitLoss, "PnL is not correct after adjustment");
        assertEq(
            marketSummary.profitLossTotalByLongs,
            marketSummaryBefore.profitLossTotalByLongs,
            "Total PnL is not correct after adjustment"
        );
        assertGt(
            collateralPerShare,
            collateralPerShareBefore,
            "Collateral per share should increase after adjustment because of trade fee"
        );
    }

    function test_adjust_position_margin_increase_size_decrease_price_increase() public {
        vm.startPrank(alice);

        uint256 aliceCollateralBalanceBefore = WETH.balanceOf(alice);
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // 10 ETH margin, 30 ETH size (4x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 newCollateralPrice = 2000e8;
        // 100% increase
        setWethPrice(newCollateralPrice);

        FlatcoinStructs.Position memory positionBefore = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummaryBefore = leverageModProxy.getMarketSummary();
        uint256 collateralPerShareBefore = stableModProxy.stableCollateralPerShare();

        // +10 ETH margin, -10 ETH size
        uint256 adjustmentTradeFee = announceAndExecuteLeverageAdjust({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            marginAdjustment: 10e18,
            additionalSizeAdjustment: -10e18,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        // Trade fee is taken from user during size adjustments when margin adjustment >= 0
        assertEq(
            aliceCollateralBalanceBefore -
                mockKeeperFee.getKeeperFee() *
                3 -
                leverageModProxy.getTradeFee(30e18) -
                stableDeposit -
                20e18 -
                adjustmentTradeFee,
            WETH.balanceOf(alice),
            "Alice collateral balance incorrect"
        );

        FlatcoinStructs.Position memory position = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummary = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummary = leverageModProxy.getMarketSummary();
        uint256 collateralPerShare = stableModProxy.stableCollateralPerShare();

        assertEq(position.entryPrice, 500e18, "Entry price is not correct after adjustment");
        assertEq(
            position.marginDeposited,
            positionBefore.marginDeposited + 10e18,
            "Margin is not correct after adjustment"
        );
        assertEq(
            position.additionalSize,
            positionBefore.additionalSize - 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(positionSummary.profitLoss, positionSummaryBefore.profitLoss, "PnL is not correct after adjustment");
        assertEq(
            marketSummary.profitLossTotalByLongs,
            marketSummaryBefore.profitLossTotalByLongs,
            "Total PnL is not correct after adjustment"
        );
        assertGt(
            collateralPerShare,
            collateralPerShareBefore,
            "Collateral per share should increase after adjustment because of trade fee"
        );
    }

    function test_adjust_position_margin_decrease_size_increase_price_increase() public {
        vm.startPrank(alice);

        uint256 aliceCollateralBalanceBefore = WETH.balanceOf(alice);
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // 10 ETH margin, 30 ETH size (4x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 newCollateralPrice = 2000e8;
        // 100% increase
        setWethPrice(newCollateralPrice);

        FlatcoinStructs.Position memory positionBefore = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummaryBefore = leverageModProxy.getMarketSummary();
        uint256 collateralPerShareBefore = stableModProxy.stableCollateralPerShare();

        // -1 ETH margin, +10 ETH size
        uint256 adjustmentTradeFee = announceAndExecuteLeverageAdjust({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            marginAdjustment: -1e18,
            additionalSizeAdjustment: 10e18,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        // Trade fee is taken from existing margin during size adjustments when margin adjustment < 0
        assertEq(
            aliceCollateralBalanceBefore -
                mockKeeperFee.getKeeperFee() *
                2 -
                leverageModProxy.getTradeFee(30e18) -
                stableDeposit -
                10e18 +
                1e18,
            WETH.balanceOf(alice),
            "Alice collateral balance incorrect"
        );

        FlatcoinStructs.Position memory position = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummary = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummary = leverageModProxy.getMarketSummary();
        uint256 collateralPerShare = stableModProxy.stableCollateralPerShare();

        assertEq(position.entryPrice, 1250e18, "Entry price is not correct after adjustment");
        assertEq(
            position.marginDeposited,
            positionBefore.marginDeposited - 1e18 - adjustmentTradeFee - mockKeeperFee.getKeeperFee(),
            "Margin is not correct after adjustment"
        );
        assertEq(
            position.additionalSize,
            positionBefore.additionalSize + 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(positionSummary.profitLoss, positionSummaryBefore.profitLoss, "PnL is not correct after adjustment");
        assertEq(
            marketSummary.profitLossTotalByLongs,
            marketSummaryBefore.profitLossTotalByLongs,
            "Total PnL is not correct after adjustment"
        );
        assertGt(
            collateralPerShare,
            collateralPerShareBefore,
            "Collateral per share should increase after adjustment because of trade fee"
        );
    }

    function test_adjust_position_margin_decrease_size_decrease_price_increase() public {
        vm.startPrank(alice);

        uint256 aliceCollateralBalanceBefore = WETH.balanceOf(alice);
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // 10 ETH margin, 30 ETH size (4x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 newCollateralPrice = 2000e8;
        // 100% increase
        setWethPrice(newCollateralPrice);

        FlatcoinStructs.Position memory positionBefore = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummaryBefore = leverageModProxy.getMarketSummary();
        uint256 collateralPerShareBefore = stableModProxy.stableCollateralPerShare();

        // -1 ETH margin, -10 ETH size
        uint256 adjustmentTradeFee = announceAndExecuteLeverageAdjust({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            marginAdjustment: -1e18,
            additionalSizeAdjustment: -10e18,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        // Trade fee is taken from existing margin during size adjustments when margin adjustment < 0
        assertEq(
            aliceCollateralBalanceBefore -
                mockKeeperFee.getKeeperFee() *
                2 -
                leverageModProxy.getTradeFee(30e18) -
                stableDeposit -
                10e18 +
                1e18,
            WETH.balanceOf(alice),
            "Alice collateral balance incorrect"
        );

        FlatcoinStructs.Position memory position = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummary = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummary = leverageModProxy.getMarketSummary();
        uint256 collateralPerShare = stableModProxy.stableCollateralPerShare();

        assertEq(position.entryPrice, 500e18, "Entry price is not correct after adjustment");
        assertEq(
            position.marginDeposited,
            positionBefore.marginDeposited - 1e18 - adjustmentTradeFee - mockKeeperFee.getKeeperFee(),
            "Margin is not correct after adjustment"
        );
        assertEq(
            position.additionalSize,
            positionBefore.additionalSize - 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(positionSummary.profitLoss, positionSummaryBefore.profitLoss, "PnL is not correct after adjustment");
        assertEq(
            marketSummary.profitLossTotalByLongs,
            marketSummaryBefore.profitLossTotalByLongs,
            "Total PnL is not correct after adjustment"
        );
        assertGt(
            collateralPerShare,
            collateralPerShareBefore,
            "Collateral per share should increase after adjustment because of trade fee"
        );
    }

    function test_adjust_position_margin_decrease_price_increase() public {
        vm.startPrank(alice);

        uint256 aliceCollateralBalanceBefore = WETH.balanceOf(alice);
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // 10 ETH margin, 30 ETH size (4x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 newCollateralPrice = 2000e8;
        // 100% increase
        setWethPrice(newCollateralPrice);

        FlatcoinStructs.Position memory positionBefore = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummaryBefore = leverageModProxy.getMarketSummary();
        uint256 collateralPerShareBefore = stableModProxy.stableCollateralPerShare();

        // -1 ETH margin, no change in size
        uint256 adjustmentTradeFee = announceAndExecuteLeverageAdjust({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            marginAdjustment: -1e18,
            additionalSizeAdjustment: 0,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        assertEq(adjustmentTradeFee, 0, "Trade fee should be 0 as no size was adjusted");
        // Trade fee is taken from existing margin during size adjustments when margin adjustment < 0
        assertEq(
            aliceCollateralBalanceBefore -
                mockKeeperFee.getKeeperFee() *
                2 -
                leverageModProxy.getTradeFee(30e18) -
                stableDeposit -
                10e18 +
                1e18,
            WETH.balanceOf(alice),
            "Alice collateral balance incorrect"
        );

        FlatcoinStructs.Position memory position = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummary = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummary = leverageModProxy.getMarketSummary();
        uint256 collateralPerShare = stableModProxy.stableCollateralPerShare();

        assertEq(
            position.entryPrice,
            1000e18,
            "Entry price should match price during open, as no additional size was added"
        );
        assertEq(
            position.marginDeposited,
            positionBefore.marginDeposited - 1e18 - mockKeeperFee.getKeeperFee(),
            "Margin is not correct after adjustment"
        );
        assertEq(position.additionalSize, positionBefore.additionalSize, "Size is not correct after adjustment");
        assertEq(positionSummary.profitLoss, positionSummaryBefore.profitLoss, "PnL is not correct after adjustment");
        assertEq(
            marketSummary.profitLossTotalByLongs,
            marketSummaryBefore.profitLossTotalByLongs,
            "Total PnL is not correct after adjustment"
        );
        assertEq(
            collateralPerShare,
            collateralPerShareBefore,
            "Collateral per share should not change after adjustment"
        );
    }

    function test_adjust_position_size_decrease_price_increase() public {
        vm.startPrank(alice);

        uint256 aliceCollateralBalanceBefore = WETH.balanceOf(alice);
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // 10 ETH margin, 30 ETH size (4x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 newCollateralPrice = 2000e8;
        // 100% increase
        setWethPrice(newCollateralPrice);

        FlatcoinStructs.Position memory positionBefore = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummaryBefore = leverageModProxy.getMarketSummary();
        uint256 collateralPerShareBefore = stableModProxy.stableCollateralPerShare();

        // -10 ETH size, no change in margin
        uint256 adjustmentTradeFee = announceAndExecuteLeverageAdjust({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            marginAdjustment: 0,
            additionalSizeAdjustment: -10e18,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        // Trade fee is taken from existing margin during size adjustments when margin adjustment = 0
        assertEq(
            aliceCollateralBalanceBefore -
                mockKeeperFee.getKeeperFee() *
                2 -
                leverageModProxy.getTradeFee(30e18) -
                stableDeposit -
                10e18,
            WETH.balanceOf(alice),
            "Alice collateral balance incorrect"
        );

        FlatcoinStructs.Position memory position = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummary = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummary = leverageModProxy.getMarketSummary();
        uint256 collateralPerShare = stableModProxy.stableCollateralPerShare();

        assertEq(position.entryPrice, 500e18, "Entry price is not correct after adjustment");
        assertEq(
            position.marginDeposited,
            positionBefore.marginDeposited - mockKeeperFee.getKeeperFee() - adjustmentTradeFee,
            "Margin is not correct after adjustment"
        );
        assertEq(
            position.additionalSize,
            positionBefore.additionalSize - 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(positionSummary.profitLoss, positionSummaryBefore.profitLoss, "PnL is not correct after adjustment");
        assertEq(
            marketSummary.profitLossTotalByLongs,
            marketSummaryBefore.profitLossTotalByLongs,
            "Total PnL is not correct after adjustment"
        );
        assertGt(
            collateralPerShare,
            collateralPerShareBefore,
            "Collateral per share should increase after adjustment because of trade fee"
        );
    }

    /**
     * Price Decrease Suites (8 Scenarios)
     */

    function test_adjust_position_margin_increase_price_decrease() public {
        vm.startPrank(alice);

        uint256 aliceCollateralBalanceBefore = WETH.balanceOf(alice);
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // 10 ETH margin, 30 ETH size (4x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 newCollateralPrice = 800e8;
        setWethPrice(newCollateralPrice);

        FlatcoinStructs.Position memory positionBefore = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummaryBefore = leverageModProxy.getMarketSummary();
        uint256 collateralPerShareBefore = stableModProxy.stableCollateralPerShare();

        // +5 ETH margin, no change in size
        uint256 adjustmentTradeFee = announceAndExecuteLeverageAdjust({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            marginAdjustment: 5e18,
            additionalSizeAdjustment: 0,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        assertEq(adjustmentTradeFee, 0, "Trade fee should be 0 as no size was adjusted");
        // Trade fee is not taken (0) when size is not adjusted
        assertEq(
            aliceCollateralBalanceBefore -
                mockKeeperFee.getKeeperFee() *
                3 -
                leverageModProxy.getTradeFee(30e18) -
                stableDeposit -
                15e18,
            WETH.balanceOf(alice),
            "Alice collateral balance incorrect"
        );

        FlatcoinStructs.Position memory position = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummary = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummary = leverageModProxy.getMarketSummary();
        uint256 collateralPerShare = stableModProxy.stableCollateralPerShare();

        assertEq(
            position.entryPrice,
            1000e18,
            "Entry price should match price during open, as no additional size was added"
        );
        assertEq(
            position.marginDeposited,
            positionBefore.marginDeposited + 5e18,
            "Margin is not correct after adjustment"
        );
        assertEq(position.additionalSize, positionBefore.additionalSize, "Size is not correct after adjustment");
        assertEq(positionSummary.profitLoss, positionSummaryBefore.profitLoss, "PnL is not correct after adjustment");
        assertEq(
            marketSummary.profitLossTotalByLongs,
            marketSummaryBefore.profitLossTotalByLongs,
            "Total PnL is not correct after adjustment"
        );
        assertEq(
            collateralPerShare,
            collateralPerShareBefore,
            "Collateral per share should not change after adjustment"
        );
    }

    function test_adjust_position_size_increase_price_decrease() public {
        vm.startPrank(alice);

        uint256 aliceCollateralBalanceBefore = WETH.balanceOf(alice);
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // 10 ETH margin, 30 ETH size (4x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 newCollateralPrice = 800e8;
        setWethPrice(newCollateralPrice);

        FlatcoinStructs.Position memory positionBefore = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummaryBefore = leverageModProxy.getMarketSummary();
        uint256 collateralPerShareBefore = stableModProxy.stableCollateralPerShare();

        // +10 ETH size, no change in margin
        uint256 adjustmentTradeFee = announceAndExecuteLeverageAdjust({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            marginAdjustment: 0,
            additionalSizeAdjustment: 10e18,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        // Trade fee is taken from existing margin during size adjustments when margin adjustment = 0
        assertEq(
            aliceCollateralBalanceBefore -
                mockKeeperFee.getKeeperFee() *
                2 -
                leverageModProxy.getTradeFee(30e18) -
                stableDeposit -
                10e18,
            WETH.balanceOf(alice),
            "Alice collateral balance incorrect"
        );

        FlatcoinStructs.Position memory position = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummary = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummary = leverageModProxy.getMarketSummary();
        uint256 collateralPerShare = stableModProxy.stableCollateralPerShare();

        assertEq(position.entryPrice, 950e18, "Entry price is not correct after adjustment");
        assertEq(
            position.marginDeposited,
            positionBefore.marginDeposited - mockKeeperFee.getKeeperFee() - adjustmentTradeFee,
            "Margin is not correct after adjustment"
        );
        assertEq(
            position.additionalSize,
            positionBefore.additionalSize + 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(positionSummary.profitLoss, positionSummaryBefore.profitLoss, "PnL is not correct after adjustment");
        assertEq(
            marketSummary.profitLossTotalByLongs,
            marketSummaryBefore.profitLossTotalByLongs,
            "Total PnL is not correct after adjustment"
        );
        assertGt(
            collateralPerShare,
            collateralPerShareBefore,
            "Collateral per share should increase after adjustment because of trade fee"
        );
    }

    function test_adjust_position_margin_increase_size_increase_price_decrease() public {
        vm.startPrank(alice);

        uint256 aliceCollateralBalanceBefore = WETH.balanceOf(alice);
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // 10 ETH margin, 30 ETH size (4x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 newCollateralPrice = 800e8;
        setWethPrice(newCollateralPrice);

        FlatcoinStructs.Position memory positionBefore = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummaryBefore = leverageModProxy.getMarketSummary();
        uint256 collateralPerShareBefore = stableModProxy.stableCollateralPerShare();

        // +10 ETH margin, +10 ETH size
        uint256 adjustmentTradeFee = announceAndExecuteLeverageAdjust({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            marginAdjustment: 10e18,
            additionalSizeAdjustment: 10e18,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        // Trade fee is taken from user during size adjustments when margin adjustment >= 0
        assertEq(
            aliceCollateralBalanceBefore -
                mockKeeperFee.getKeeperFee() *
                3 -
                leverageModProxy.getTradeFee(30e18) -
                stableDeposit -
                20e18 -
                adjustmentTradeFee,
            WETH.balanceOf(alice),
            "Alice collateral balance incorrect"
        );

        FlatcoinStructs.Position memory position = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummary = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummary = leverageModProxy.getMarketSummary();
        uint256 collateralPerShare = stableModProxy.stableCollateralPerShare();

        assertEq(position.entryPrice, 950e18, "Entry price is not correct after adjustment");
        assertEq(
            position.marginDeposited,
            positionBefore.marginDeposited + 10e18,
            "Margin is not correct after adjustment"
        );
        assertEq(
            position.additionalSize,
            positionBefore.additionalSize + 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(positionSummary.profitLoss, positionSummaryBefore.profitLoss, "PnL is not correct after adjustment");
        assertEq(
            marketSummary.profitLossTotalByLongs,
            marketSummaryBefore.profitLossTotalByLongs,
            "Total PnL is not correct after adjustment"
        );
        assertGt(
            collateralPerShare,
            collateralPerShareBefore,
            "Collateral per share should increase after adjustment because of trade fee"
        );
    }

    function test_adjust_position_margin_increase_size_decrease_price_decrease() public {
        vm.startPrank(alice);

        uint256 aliceCollateralBalanceBefore = WETH.balanceOf(alice);
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // 10 ETH margin, 30 ETH size (4x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 newCollateralPrice = 800e8;
        setWethPrice(newCollateralPrice);

        FlatcoinStructs.Position memory positionBefore = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummaryBefore = leverageModProxy.getMarketSummary();
        uint256 collateralPerShareBefore = stableModProxy.stableCollateralPerShare();

        // +10 ETH margin, -10 ETH size
        uint256 adjustmentTradeFee = announceAndExecuteLeverageAdjust({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            marginAdjustment: 10e18,
            additionalSizeAdjustment: -10e18,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        // Trade fee is taken from user during size adjustments when margin adjustment >= 0
        assertEq(
            aliceCollateralBalanceBefore -
                mockKeeperFee.getKeeperFee() *
                3 -
                leverageModProxy.getTradeFee(30e18) -
                stableDeposit -
                20e18 -
                adjustmentTradeFee,
            WETH.balanceOf(alice),
            "Alice collateral balance incorrect"
        );

        FlatcoinStructs.Position memory position = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummary = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummary = leverageModProxy.getMarketSummary();
        uint256 collateralPerShare = stableModProxy.stableCollateralPerShare();

        assertEq(position.entryPrice, 1100e18, "Entry price is not correct after adjustment");
        assertEq(
            position.marginDeposited,
            positionBefore.marginDeposited + 10e18,
            "Margin is not correct after adjustment"
        );
        assertEq(
            position.additionalSize,
            positionBefore.additionalSize - 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(positionSummary.profitLoss, positionSummaryBefore.profitLoss, "PnL is not correct after adjustment");
        assertEq(
            marketSummary.profitLossTotalByLongs,
            marketSummaryBefore.profitLossTotalByLongs,
            "Total PnL is not correct after adjustment"
        );
        assertGt(
            collateralPerShare,
            collateralPerShareBefore,
            "Collateral per share should increase after adjustment because of trade fee"
        );
    }

    function test_adjust_position_margin_decrease_size_increase_price_decrease() public {
        vm.startPrank(alice);

        uint256 aliceCollateralBalanceBefore = WETH.balanceOf(alice);
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // 10 ETH margin, 30 ETH size (4x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 newCollateralPrice = 800e8;
        setWethPrice(newCollateralPrice);

        FlatcoinStructs.Position memory positionBefore = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummaryBefore = leverageModProxy.getMarketSummary();
        uint256 collateralPerShareBefore = stableModProxy.stableCollateralPerShare();

        // -1 ETH margin, +10 ETH size
        uint256 adjustmentTradeFee = announceAndExecuteLeverageAdjust({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            marginAdjustment: -1e18,
            additionalSizeAdjustment: 10e18,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        // Trade fee is taken from existing margin during size adjustments when margin adjustment < 0
        assertEq(
            aliceCollateralBalanceBefore -
                mockKeeperFee.getKeeperFee() *
                2 -
                leverageModProxy.getTradeFee(30e18) -
                stableDeposit -
                10e18 +
                1e18,
            WETH.balanceOf(alice),
            "Alice collateral balance incorrect"
        );

        FlatcoinStructs.Position memory position = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummary = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummary = leverageModProxy.getMarketSummary();
        uint256 collateralPerShare = stableModProxy.stableCollateralPerShare();

        assertEq(position.entryPrice, 950e18, "Entry price is not correct after adjustment");
        assertEq(
            position.marginDeposited,
            positionBefore.marginDeposited - 1e18 - adjustmentTradeFee - mockKeeperFee.getKeeperFee(),
            "Margin is not correct after adjustment"
        );
        assertEq(
            position.additionalSize,
            positionBefore.additionalSize + 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(positionSummary.profitLoss, positionSummaryBefore.profitLoss, "PnL is not correct after adjustment");
        assertEq(
            marketSummary.profitLossTotalByLongs,
            marketSummaryBefore.profitLossTotalByLongs,
            "Total PnL is not correct after adjustment"
        );
        assertGt(
            collateralPerShare,
            collateralPerShareBefore,
            "Collateral per share should increase after adjustment because of trade fee"
        );
    }

    function test_adjust_position_margin_decrease_size_decrease_price_decrease() public {
        vm.startPrank(alice);

        uint256 aliceCollateralBalanceBefore = WETH.balanceOf(alice);
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // 10 ETH margin, 30 ETH size (4x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 newCollateralPrice = 800e8;
        setWethPrice(newCollateralPrice);

        FlatcoinStructs.Position memory positionBefore = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummaryBefore = leverageModProxy.getMarketSummary();
        uint256 collateralPerShareBefore = stableModProxy.stableCollateralPerShare();

        // -1 ETH margin, -10 ETH size
        uint256 adjustmentTradeFee = announceAndExecuteLeverageAdjust({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            marginAdjustment: -1e18,
            additionalSizeAdjustment: -10e18,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        // Trade fee is taken from existing margin during size adjustments when margin adjustment < 0
        assertEq(
            aliceCollateralBalanceBefore -
                mockKeeperFee.getKeeperFee() *
                2 -
                leverageModProxy.getTradeFee(30e18) -
                stableDeposit -
                10e18 +
                1e18,
            WETH.balanceOf(alice),
            "Alice collateral balance incorrect"
        );

        FlatcoinStructs.Position memory position = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummary = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummary = leverageModProxy.getMarketSummary();
        uint256 collateralPerShare = stableModProxy.stableCollateralPerShare();

        assertEq(position.entryPrice, 1100e18, "Entry price is not correct after adjustment");
        assertEq(
            position.marginDeposited,
            positionBefore.marginDeposited - 1e18 - adjustmentTradeFee - mockKeeperFee.getKeeperFee(),
            "Margin is not correct after adjustment"
        );
        assertEq(
            position.additionalSize,
            positionBefore.additionalSize - 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(positionSummary.profitLoss, positionSummaryBefore.profitLoss, "PnL is not correct after adjustment");
        assertEq(
            marketSummary.profitLossTotalByLongs,
            marketSummaryBefore.profitLossTotalByLongs,
            "Total PnL is not correct after adjustment"
        );
        assertGt(
            collateralPerShare,
            collateralPerShareBefore,
            "Collateral per share should increase after adjustment because of trade fee"
        );
    }

    function test_adjust_position_margin_decrease_price_decrease() public {
        vm.startPrank(alice);

        uint256 aliceCollateralBalanceBefore = WETH.balanceOf(alice);
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // 10 ETH margin, 30 ETH size (4x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 newCollateralPrice = 800e8;
        setWethPrice(newCollateralPrice);

        FlatcoinStructs.Position memory positionBefore = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummaryBefore = leverageModProxy.getMarketSummary();
        uint256 collateralPerShareBefore = stableModProxy.stableCollateralPerShare();

        // -1 ETH margin, no change in size
        uint256 adjustmentTradeFee = announceAndExecuteLeverageAdjust({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            marginAdjustment: -1e18,
            additionalSizeAdjustment: 0,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        assertEq(adjustmentTradeFee, 0, "Trade fee should be 0 as no size was adjusted");
        // Trade fee is taken from existing margin during size adjustments when margin adjustment < 0
        assertEq(
            aliceCollateralBalanceBefore -
                mockKeeperFee.getKeeperFee() *
                2 -
                leverageModProxy.getTradeFee(30e18) -
                stableDeposit -
                10e18 +
                1e18,
            WETH.balanceOf(alice),
            "Alice collateral balance incorrect"
        );

        FlatcoinStructs.Position memory position = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummary = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummary = leverageModProxy.getMarketSummary();
        uint256 collateralPerShare = stableModProxy.stableCollateralPerShare();

        assertEq(
            position.entryPrice,
            1000e18,
            "Entry price should match price during open, as no additional size was added"
        );
        assertEq(
            position.marginDeposited,
            positionBefore.marginDeposited - 1e18 - mockKeeperFee.getKeeperFee(),
            "Margin is not correct after adjustment"
        );
        assertEq(position.additionalSize, positionBefore.additionalSize, "Size is not correct after adjustment");
        assertEq(positionSummary.profitLoss, positionSummaryBefore.profitLoss, "PnL is not correct after adjustment");
        assertEq(
            marketSummary.profitLossTotalByLongs,
            marketSummaryBefore.profitLossTotalByLongs,
            "Total PnL is not correct after adjustment"
        );
        assertEq(
            collateralPerShare,
            collateralPerShareBefore,
            "Collateral per share should not change after adjustment"
        );
    }

    function test_adjust_position_size_decrease_price_decrease() public {
        vm.startPrank(alice);

        uint256 aliceCollateralBalanceBefore = WETH.balanceOf(alice);
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // 10 ETH margin, 30 ETH size (4x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 newCollateralPrice = 800e8;
        setWethPrice(newCollateralPrice);

        FlatcoinStructs.Position memory positionBefore = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummaryBefore = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummaryBefore = leverageModProxy.getMarketSummary();
        uint256 collateralPerShareBefore = stableModProxy.stableCollateralPerShare();

        // -10 ETH size, no change in margin
        uint256 adjustmentTradeFee = announceAndExecuteLeverageAdjust({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            marginAdjustment: 0,
            additionalSizeAdjustment: -10e18,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        // Trade fee is taken from existing margin during size adjustments when margin adjustment = 0
        assertEq(
            aliceCollateralBalanceBefore -
                mockKeeperFee.getKeeperFee() *
                2 -
                stableDeposit -
                10e18 -
                leverageModProxy.getTradeFee(30e18),
            WETH.balanceOf(alice),
            "Alice collateral balance incorrect"
        );

        FlatcoinStructs.Position memory position = vaultProxy.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummary = leverageModProxy.getPositionSummary(tokenId);
        FlatcoinStructs.MarketSummary memory marketSummary = leverageModProxy.getMarketSummary();
        uint256 collateralPerShare = stableModProxy.stableCollateralPerShare();

        assertEq(position.entryPrice, 1100e18, "Entry price is not correct after adjustment");
        assertEq(
            position.marginDeposited,
            positionBefore.marginDeposited - mockKeeperFee.getKeeperFee() - adjustmentTradeFee,
            "Margin is not correct after adjustment"
        );
        assertEq(
            position.additionalSize,
            positionBefore.additionalSize - 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(positionSummary.profitLoss, positionSummaryBefore.profitLoss, "PnL is not correct after adjustment");
        assertEq(
            marketSummary.profitLossTotalByLongs,
            marketSummaryBefore.profitLossTotalByLongs,
            "Total PnL is not correct after adjustment"
        );
        assertGt(
            collateralPerShare,
            collateralPerShareBefore,
            "Collateral per share should increase after adjustment because of trade fee"
        );
    }
}
