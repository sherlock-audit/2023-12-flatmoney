// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {ExpectRevert} from "../../helpers/ExpectRevert.sol";
import {OrderHelpers} from "../../helpers/OrderHelpers.sol";
import {FlatcoinErrors} from "../../../src/libraries/FlatcoinErrors.sol";
import {FlatcoinStructs} from "../../../src/libraries/FlatcoinStructs.sol";

import "forge-std/console2.sol";

contract AdjustPositionTest is OrderHelpers, ExpectRevert {
    struct StateBefore {
        FlatcoinStructs.Position position;
        FlatcoinStructs.PositionSummary positionSummary;
        FlatcoinStructs.MarketSummary marketSummary;
        FlatcoinStructs.GlobalPositions globalPositions;
        uint256 collateralPerShare;
    }

    struct StateAfter {
        FlatcoinStructs.Position position;
        FlatcoinStructs.PositionSummary positionSummary;
        FlatcoinStructs.MarketSummary marketSummary;
        FlatcoinStructs.GlobalPositions globalPositions;
        uint256 collateralPerShare;
    }

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
            expectedErrorSignature: "LeverageTooLow(uint256,uint256)",
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
            expectedErrorSignature: "NotTokenOwner(uint256,address)",
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
            expectedErrorSignature: "ZeroValue(string)",
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
            expectedErrorSignature: "ValueNotPositive(string)",
            errorData: abi.encodeWithSelector(
                FlatcoinErrors.ValueNotPositive.selector,
                "newMarginAfterSettlement|newAdditionalSize"
            )
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
            expectedErrorSignature: "PositionCreatesBadDebt()",
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
            _marginMin: 0.75e18,
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
                int256(-9.29e18) + int256(leverageModProxy.getTradeFee(90e18)) + int256(mockKeeperFee.getKeeperFee()),
                90e18,
                0
            ),
            expectedErrorSignature: "MarginTooSmall(uint256,uint256)",
            errorData: abi.encodeWithSelector(FlatcoinErrors.MarginTooSmall.selector, 0.75e18, 0.71e18)
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
            expectedErrorSignature: "ValueNotPositive(string)",
            errorData: abi.encodeWithSelector(
                FlatcoinErrors.ValueNotPositive.selector,
                "newMarginAfterSettlement|newAdditionalSize"
            )
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

        StateBefore memory stateBeforeAdjustment = StateBefore({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

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

        // Trade fee is not taken (0) when size is not adjusted
        assertEq(adjustmentTradeFee, 0, "Trade fee should be 0 as no size was adjusted");

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

        StateAfter memory stateAfterAdjustment = StateAfter({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

        assertEq(
            stateAfterAdjustment.position.lastPrice,
            newCollateralPrice * 1e10,
            "Last price should have been reset to current price"
        );
        assertEq(
            stateAfterAdjustment.position.marginDeposited,
            uint256(stateBeforeAdjustment.positionSummary.marginAfterSettlement + 5e18),
            "Margin is not correct after adjustment"
        );
        assertEq(
            stateAfterAdjustment.position.additionalSize,
            stateBeforeAdjustment.position.additionalSize,
            "Size is not correct after adjustment"
        );
        assertEq(stateAfterAdjustment.positionSummary.profitLoss, 0, "PnL should have been settled after adjustment");
        assertEq(
            stateAfterAdjustment.globalPositions.marginDepositedTotal,
            uint256(
                int256(stateBeforeAdjustment.globalPositions.marginDepositedTotal) +
                    stateBeforeAdjustment.marketSummary.profitLossTotalByLongs +
                    stateBeforeAdjustment.marketSummary.accruedFundingTotalByLongs +
                    5e18
            ),
            "Global margin deposited should have been set to global margin after settlement + margin adjustment"
        );
        assertEq(
            stateAfterAdjustment.marketSummary.profitLossTotalByLongs,
            0,
            "Total PnL should have been reset after adjustment"
        );
        assertEq(
            stateAfterAdjustment.collateralPerShare,
            stateBeforeAdjustment.collateralPerShare,
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

        StateBefore memory stateBeforeAdjustment = StateBefore({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

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

        StateAfter memory stateAfterAdjustment = StateAfter({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

        assertEq(
            stateAfterAdjustment.position.lastPrice,
            newCollateralPrice * 1e10,
            "Last price should have been reset to current price"
        );
        assertEq(
            stateAfterAdjustment.position.marginDeposited,
            uint256(
                stateBeforeAdjustment.positionSummary.marginAfterSettlement -
                    int256(mockKeeperFee.getKeeperFee()) -
                    int256(adjustmentTradeFee)
            ),
            "Margin is not correct after adjustment"
        );
        assertEq(
            stateAfterAdjustment.position.additionalSize,
            stateBeforeAdjustment.position.additionalSize + 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(stateAfterAdjustment.positionSummary.profitLoss, 0, "PnL should have been settled after adjustment");
        assertEq(
            stateAfterAdjustment.marketSummary.profitLossTotalByLongs,
            0,
            "Total PnL should have been reset after adjustment"
        );
        assertEq(
            stateAfterAdjustment.globalPositions.marginDepositedTotal,
            uint256(
                int256(stateBeforeAdjustment.globalPositions.marginDepositedTotal) +
                    stateBeforeAdjustment.marketSummary.profitLossTotalByLongs +
                    stateBeforeAdjustment.marketSummary.accruedFundingTotalByLongs -
                    int256(mockKeeperFee.getKeeperFee()) -
                    int256(adjustmentTradeFee)
            ),
            "Global margin deposited should have been set to global margin after settlement + margin adjustment"
        );
        assertGt(
            stateAfterAdjustment.collateralPerShare,
            stateBeforeAdjustment.collateralPerShare,
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

        StateBefore memory stateBeforeAdjustment = StateBefore({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

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

        StateAfter memory stateAfterAdjustment = StateAfter({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

        assertEq(
            stateAfterAdjustment.position.lastPrice,
            newCollateralPrice * 1e10,
            "Last price should have been reset to current price"
        );
        assertEq(
            stateAfterAdjustment.position.marginDeposited,
            uint256(stateBeforeAdjustment.positionSummary.marginAfterSettlement + 10e18),
            "Margin is not correct after adjustment"
        );
        assertEq(
            stateAfterAdjustment.position.additionalSize,
            stateBeforeAdjustment.position.additionalSize + 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(stateAfterAdjustment.positionSummary.profitLoss, 0, "PnL should have been settled after adjustment");
        assertEq(
            stateAfterAdjustment.marketSummary.profitLossTotalByLongs,
            0,
            "Total PnL should have been reset after adjustment"
        );
        assertEq(
            stateAfterAdjustment.globalPositions.marginDepositedTotal,
            uint256(
                int256(stateBeforeAdjustment.globalPositions.marginDepositedTotal) +
                    stateBeforeAdjustment.marketSummary.profitLossTotalByLongs +
                    stateBeforeAdjustment.marketSummary.accruedFundingTotalByLongs +
                    10e18
            ),
            "Global margin deposited should have been set to global margin after settlement + margin adjustment"
        );
        assertGt(
            stateAfterAdjustment.collateralPerShare,
            stateBeforeAdjustment.collateralPerShare,
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

        StateBefore memory stateBeforeAdjustment = StateBefore({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

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

        StateAfter memory stateAfterAdjustment = StateAfter({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

        assertEq(
            stateAfterAdjustment.position.lastPrice,
            newCollateralPrice * 1e10,
            "Last price should have been reset to current price"
        );
        assertEq(
            stateAfterAdjustment.position.marginDeposited,
            uint256(stateBeforeAdjustment.positionSummary.marginAfterSettlement + 10e18),
            "Margin is not correct after adjustment"
        );
        assertEq(
            stateAfterAdjustment.position.additionalSize,
            stateBeforeAdjustment.position.additionalSize - 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(stateAfterAdjustment.positionSummary.profitLoss, 0, "PnL should have been settled after adjustment");
        assertEq(
            stateAfterAdjustment.marketSummary.profitLossTotalByLongs,
            0,
            "Total PnL should have been reset after adjustment"
        );
        assertEq(
            stateAfterAdjustment.globalPositions.marginDepositedTotal,
            uint256(
                int256(stateBeforeAdjustment.globalPositions.marginDepositedTotal) +
                    stateBeforeAdjustment.marketSummary.profitLossTotalByLongs +
                    stateBeforeAdjustment.marketSummary.accruedFundingTotalByLongs +
                    10e18
            ),
            "Global margin deposited should have been set to global margin after settlement + margin adjustment"
        );
        assertGt(
            stateAfterAdjustment.collateralPerShare,
            stateBeforeAdjustment.collateralPerShare,
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

        StateBefore memory stateBeforeAdjustment = StateBefore({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

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

        StateAfter memory stateAfterAdjustment = StateAfter({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

        assertEq(
            stateAfterAdjustment.position.lastPrice,
            newCollateralPrice * 1e10,
            "Last price should have been reset to current price"
        );
        assertEq(
            stateAfterAdjustment.position.marginDeposited,
            uint256(
                stateBeforeAdjustment.positionSummary.marginAfterSettlement -
                    1e18 -
                    int256(adjustmentTradeFee) -
                    int256(mockKeeperFee.getKeeperFee())
            ),
            "Margin is not correct after adjustment"
        );
        assertEq(
            stateAfterAdjustment.position.additionalSize,
            stateBeforeAdjustment.position.additionalSize + 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(stateAfterAdjustment.positionSummary.profitLoss, 0, "PnL should have been settled after adjustment");
        assertEq(
            stateAfterAdjustment.marketSummary.profitLossTotalByLongs,
            0,
            "Total PnL should have been reset after adjustment"
        );
        assertEq(
            stateAfterAdjustment.globalPositions.marginDepositedTotal,
            uint256(
                int256(stateBeforeAdjustment.globalPositions.marginDepositedTotal) +
                    stateBeforeAdjustment.marketSummary.profitLossTotalByLongs +
                    stateBeforeAdjustment.marketSummary.accruedFundingTotalByLongs -
                    1e18 -
                    int256(adjustmentTradeFee) -
                    int256(mockKeeperFee.getKeeperFee())
            ),
            "Global margin deposited should have been set to global margin after settlement + margin adjustment"
        );
        assertGt(
            stateAfterAdjustment.collateralPerShare,
            stateBeforeAdjustment.collateralPerShare,
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

        StateBefore memory stateBeforeAdjustment = StateBefore({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

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

        StateAfter memory stateAfterAdjustment = StateAfter({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

        assertEq(
            stateAfterAdjustment.position.lastPrice,
            newCollateralPrice * 1e10,
            "Last price should have been reset to current price"
        );
        assertEq(
            stateAfterAdjustment.position.marginDeposited,
            uint256(
                stateBeforeAdjustment.positionSummary.marginAfterSettlement -
                    1e18 -
                    int256(adjustmentTradeFee) -
                    int256(mockKeeperFee.getKeeperFee())
            ),
            "Margin is not correct after adjustment"
        );
        assertEq(
            stateAfterAdjustment.position.additionalSize,
            stateBeforeAdjustment.position.additionalSize - 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(stateAfterAdjustment.positionSummary.profitLoss, 0, "PnL should have been settled after adjustment");
        assertEq(
            stateAfterAdjustment.marketSummary.profitLossTotalByLongs,
            0,
            "Total PnL should have been reset after adjustment"
        );
        assertEq(
            stateAfterAdjustment.globalPositions.marginDepositedTotal,
            uint256(
                int256(stateBeforeAdjustment.globalPositions.marginDepositedTotal) +
                    stateBeforeAdjustment.marketSummary.profitLossTotalByLongs +
                    stateBeforeAdjustment.marketSummary.accruedFundingTotalByLongs -
                    1e18 -
                    int256(adjustmentTradeFee) -
                    int256(mockKeeperFee.getKeeperFee())
            ),
            "Global margin deposited should have been set to global margin after settlement + margin adjustment"
        );
        assertGt(
            stateAfterAdjustment.collateralPerShare,
            stateBeforeAdjustment.collateralPerShare,
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

        StateBefore memory stateBeforeAdjustment = StateBefore({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

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

        StateAfter memory stateAfterAdjustment = StateAfter({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

        assertEq(
            stateAfterAdjustment.position.lastPrice,
            newCollateralPrice * 1e10,
            "Last price should have been reset to current price"
        );
        assertEq(
            stateAfterAdjustment.position.marginDeposited,
            uint256(
                stateBeforeAdjustment.positionSummary.marginAfterSettlement -
                    1e18 -
                    int256(mockKeeperFee.getKeeperFee())
            ),
            "Margin is not correct after adjustment"
        );
        assertEq(
            stateAfterAdjustment.position.additionalSize,
            stateBeforeAdjustment.position.additionalSize,
            "Size is not correct after adjustment"
        );
        assertEq(stateAfterAdjustment.positionSummary.profitLoss, 0, "PnL should have been settled after adjustment");
        assertEq(
            stateAfterAdjustment.marketSummary.profitLossTotalByLongs,
            0,
            "Total PnL should have been reset after adjustment"
        );
        assertEq(
            stateAfterAdjustment.globalPositions.marginDepositedTotal,
            uint256(
                int256(stateBeforeAdjustment.globalPositions.marginDepositedTotal) +
                    stateBeforeAdjustment.marketSummary.profitLossTotalByLongs +
                    stateBeforeAdjustment.marketSummary.accruedFundingTotalByLongs -
                    1e18 -
                    int256(mockKeeperFee.getKeeperFee())
            ),
            "Global margin deposited should have been set to global margin after settlement + margin adjustment"
        );
        assertEq(
            stateAfterAdjustment.collateralPerShare,
            stateBeforeAdjustment.collateralPerShare,
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

        StateBefore memory stateBeforeAdjustment = StateBefore({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

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

        StateAfter memory stateAfterAdjustment = StateAfter({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

        assertEq(
            stateAfterAdjustment.position.lastPrice,
            newCollateralPrice * 1e10,
            "Last price should have been reset to current price"
        );
        assertEq(
            stateAfterAdjustment.position.marginDeposited,
            uint256(
                stateBeforeAdjustment.positionSummary.marginAfterSettlement -
                    int256(mockKeeperFee.getKeeperFee()) -
                    int256(adjustmentTradeFee)
            ),
            "Margin is not correct after adjustment"
        );
        assertEq(
            stateAfterAdjustment.position.additionalSize,
            stateBeforeAdjustment.position.additionalSize - 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(stateAfterAdjustment.positionSummary.profitLoss, 0, "PnL should have been settled after adjustment");
        assertEq(
            stateAfterAdjustment.marketSummary.profitLossTotalByLongs,
            0,
            "Total PnL should have been reset after adjustment"
        );
        assertEq(
            stateAfterAdjustment.globalPositions.marginDepositedTotal,
            uint256(
                int256(stateBeforeAdjustment.globalPositions.marginDepositedTotal) +
                    stateBeforeAdjustment.marketSummary.profitLossTotalByLongs +
                    stateBeforeAdjustment.marketSummary.accruedFundingTotalByLongs -
                    int256(mockKeeperFee.getKeeperFee()) -
                    int256(adjustmentTradeFee)
            ),
            "Global margin deposited should have been set to global margin after settlement + margin adjustment"
        );
        assertGt(
            stateAfterAdjustment.collateralPerShare,
            stateBeforeAdjustment.collateralPerShare,
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

        StateBefore memory stateBeforeAdjustment = StateBefore({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

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

        StateAfter memory stateAfterAdjustment = StateAfter({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

        assertEq(
            stateAfterAdjustment.position.lastPrice,
            newCollateralPrice * 1e10,
            "Last price should have been reset to current price"
        );
        assertEq(
            stateAfterAdjustment.position.marginDeposited,
            uint256(stateBeforeAdjustment.positionSummary.marginAfterSettlement + 5e18),
            "Margin is not correct after adjustment"
        );
        assertEq(
            stateAfterAdjustment.position.additionalSize,
            stateBeforeAdjustment.position.additionalSize,
            "Size is not correct after adjustment"
        );
        assertEq(stateAfterAdjustment.positionSummary.profitLoss, 0, "PnL should have been settled after adjustment");
        assertEq(
            stateAfterAdjustment.marketSummary.profitLossTotalByLongs,
            0,
            "Total PnL should have been reset after adjustment"
        );
        assertEq(
            stateAfterAdjustment.globalPositions.marginDepositedTotal,
            uint256(
                int256(stateBeforeAdjustment.globalPositions.marginDepositedTotal) +
                    stateBeforeAdjustment.marketSummary.profitLossTotalByLongs +
                    stateBeforeAdjustment.marketSummary.accruedFundingTotalByLongs +
                    5e18
            ),
            "Global margin deposited should have been set to global margin after settlement + margin adjustment"
        );
        assertEq(
            stateAfterAdjustment.collateralPerShare,
            stateBeforeAdjustment.collateralPerShare,
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

        StateBefore memory stateBeforeAdjustment = StateBefore({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

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

        StateAfter memory stateAfterAdjustment = StateAfter({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

        assertEq(
            stateAfterAdjustment.position.lastPrice,
            newCollateralPrice * 1e10,
            "Last price should have been reset to current price"
        );
        assertEq(
            stateAfterAdjustment.position.marginDeposited,
            uint256(
                stateBeforeAdjustment.positionSummary.marginAfterSettlement -
                    int256(mockKeeperFee.getKeeperFee()) -
                    int256(adjustmentTradeFee)
            ),
            "Margin is not correct after adjustment"
        );
        assertEq(
            stateAfterAdjustment.position.additionalSize,
            stateBeforeAdjustment.position.additionalSize + 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(stateAfterAdjustment.positionSummary.profitLoss, 0, "PnL should have been settled after adjustment");
        assertEq(
            stateAfterAdjustment.marketSummary.profitLossTotalByLongs,
            0,
            "Total PnL should have been reset after adjustment"
        );
        assertEq(
            stateAfterAdjustment.globalPositions.marginDepositedTotal,
            uint256(
                int256(stateBeforeAdjustment.globalPositions.marginDepositedTotal) +
                    stateBeforeAdjustment.marketSummary.profitLossTotalByLongs +
                    stateBeforeAdjustment.marketSummary.accruedFundingTotalByLongs -
                    int256(mockKeeperFee.getKeeperFee()) -
                    int256(adjustmentTradeFee)
            ),
            "Global margin deposited should have been set to global margin after settlement + margin adjustment"
        );
        assertGt(
            stateAfterAdjustment.collateralPerShare,
            stateBeforeAdjustment.collateralPerShare,
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

        StateBefore memory stateBeforeAdjustment = StateBefore({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

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

        StateAfter memory stateAfterAdjustment = StateAfter({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

        assertEq(
            stateAfterAdjustment.position.lastPrice,
            newCollateralPrice * 1e10,
            "Last price should have been reset to current price"
        );
        assertEq(
            stateAfterAdjustment.position.marginDeposited,
            uint256(stateBeforeAdjustment.positionSummary.marginAfterSettlement + 10e18),
            "Margin is not correct after adjustment"
        );
        assertEq(
            stateAfterAdjustment.position.additionalSize,
            stateBeforeAdjustment.position.additionalSize + 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(stateAfterAdjustment.positionSummary.profitLoss, 0, "PnL should have been settled after adjustment");
        assertEq(
            stateAfterAdjustment.marketSummary.profitLossTotalByLongs,
            0,
            "Total PnL should have been reset after adjustment"
        );
        assertEq(
            stateAfterAdjustment.globalPositions.marginDepositedTotal,
            uint256(
                int256(stateBeforeAdjustment.globalPositions.marginDepositedTotal) +
                    stateBeforeAdjustment.marketSummary.profitLossTotalByLongs +
                    stateBeforeAdjustment.marketSummary.accruedFundingTotalByLongs +
                    10e18
            ),
            "Global margin deposited should have been set to global margin after settlement + margin adjustment"
        );
        assertGt(
            stateAfterAdjustment.collateralPerShare,
            stateBeforeAdjustment.collateralPerShare,
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

        StateBefore memory stateBeforeAdjustment = StateBefore({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

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

        StateAfter memory stateAfterAdjustment = StateAfter({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

        assertEq(
            stateAfterAdjustment.position.lastPrice,
            newCollateralPrice * 1e10,
            "Last price should have been reset to current price"
        );
        assertEq(
            stateAfterAdjustment.position.marginDeposited,
            uint256(stateBeforeAdjustment.positionSummary.marginAfterSettlement + 10e18),
            "Margin is not correct after adjustment"
        );
        assertEq(
            stateAfterAdjustment.position.additionalSize,
            stateBeforeAdjustment.position.additionalSize - 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(stateAfterAdjustment.positionSummary.profitLoss, 0, "PnL should have been settled after adjustment");
        assertEq(
            stateAfterAdjustment.marketSummary.profitLossTotalByLongs,
            0,
            "Total PnL should have been reset after adjustment"
        );
        assertEq(
            stateAfterAdjustment.globalPositions.marginDepositedTotal,
            uint256(
                int256(stateBeforeAdjustment.globalPositions.marginDepositedTotal) +
                    stateBeforeAdjustment.marketSummary.profitLossTotalByLongs +
                    stateBeforeAdjustment.marketSummary.accruedFundingTotalByLongs +
                    10e18
            ),
            "Global margin deposited should have been set to global margin after settlement + margin adjustment"
        );
        assertGt(
            stateAfterAdjustment.collateralPerShare,
            stateBeforeAdjustment.collateralPerShare,
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

        // 10 ETH margin, 20 ETH size (3x)
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 20e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 newCollateralPrice = 800e8;
        setWethPrice(newCollateralPrice);

        StateBefore memory stateBeforeAdjustment = StateBefore({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

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
                leverageModProxy.getTradeFee(20e18) -
                stableDeposit -
                10e18 +
                1e18,
            WETH.balanceOf(alice),
            "Alice collateral balance incorrect"
        );

        StateAfter memory stateAfterAdjustment = StateAfter({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

        assertEq(
            stateAfterAdjustment.position.lastPrice,
            newCollateralPrice * 1e10,
            "Last price should have been reset to current price"
        );
        assertEq(
            stateAfterAdjustment.position.marginDeposited,
            uint256(
                stateBeforeAdjustment.positionSummary.marginAfterSettlement -
                    1e18 -
                    int256(adjustmentTradeFee) -
                    int256(mockKeeperFee.getKeeperFee())
            ),
            "Margin is not correct after adjustment"
        );
        assertEq(
            stateAfterAdjustment.position.additionalSize,
            stateBeforeAdjustment.position.additionalSize + 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(stateAfterAdjustment.positionSummary.profitLoss, 0, "PnL should have been settled after adjustment");
        assertEq(
            stateAfterAdjustment.marketSummary.profitLossTotalByLongs,
            0,
            "Total PnL should have been reset after adjustment"
        );
        assertEq(
            stateAfterAdjustment.globalPositions.marginDepositedTotal,
            uint256(
                int256(stateBeforeAdjustment.globalPositions.marginDepositedTotal) +
                    stateBeforeAdjustment.marketSummary.profitLossTotalByLongs +
                    stateBeforeAdjustment.marketSummary.accruedFundingTotalByLongs -
                    1e18 -
                    int256(adjustmentTradeFee) -
                    int256(mockKeeperFee.getKeeperFee())
            ),
            "Global margin deposited should have been set to global margin after settlement + margin adjustment"
        );
        assertGt(
            stateAfterAdjustment.collateralPerShare,
            stateBeforeAdjustment.collateralPerShare,
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

        StateBefore memory stateBeforeAdjustment = StateBefore({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

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

        StateAfter memory stateAfterAdjustment = StateAfter({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

        assertEq(
            stateAfterAdjustment.position.lastPrice,
            newCollateralPrice * 1e10,
            "Last price should have been reset to current price"
        );
        assertEq(
            stateAfterAdjustment.position.marginDeposited,
            uint256(
                stateBeforeAdjustment.positionSummary.marginAfterSettlement -
                    1e18 -
                    int256(adjustmentTradeFee) -
                    int256(mockKeeperFee.getKeeperFee())
            ),
            "Margin is not correct after adjustment"
        );
        assertEq(
            stateAfterAdjustment.position.additionalSize,
            stateBeforeAdjustment.position.additionalSize - 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(stateAfterAdjustment.positionSummary.profitLoss, 0, "PnL should have been settled after adjustment");
        assertEq(
            stateAfterAdjustment.marketSummary.profitLossTotalByLongs,
            0,
            "Total PnL should have been reset after adjustment"
        );
        assertEq(
            stateAfterAdjustment.globalPositions.marginDepositedTotal,
            uint256(
                int256(stateBeforeAdjustment.globalPositions.marginDepositedTotal) +
                    stateBeforeAdjustment.marketSummary.profitLossTotalByLongs +
                    stateBeforeAdjustment.marketSummary.accruedFundingTotalByLongs -
                    1e18 -
                    int256(adjustmentTradeFee) -
                    int256(mockKeeperFee.getKeeperFee())
            ),
            "Global margin deposited should have been set to global margin after settlement + margin adjustment"
        );
        assertGt(
            stateAfterAdjustment.collateralPerShare,
            stateBeforeAdjustment.collateralPerShare,
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

        StateBefore memory stateBeforeAdjustment = StateBefore({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

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

        StateAfter memory stateAfterAdjustment = StateAfter({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

        assertEq(
            stateAfterAdjustment.position.lastPrice,
            newCollateralPrice * 1e10,
            "Last price should have been reset to current price"
        );
        assertEq(
            stateAfterAdjustment.position.marginDeposited,
            uint256(
                stateBeforeAdjustment.positionSummary.marginAfterSettlement -
                    1e18 -
                    int256(mockKeeperFee.getKeeperFee())
            ),
            "Margin is not correct after adjustment"
        );
        assertEq(
            stateAfterAdjustment.position.additionalSize,
            stateBeforeAdjustment.position.additionalSize,
            "Size is not correct after adjustment"
        );
        assertEq(stateAfterAdjustment.positionSummary.profitLoss, 0, "PnL should have been settled after adjustment");
        assertEq(
            stateAfterAdjustment.marketSummary.profitLossTotalByLongs,
            0,
            "Total PnL should have been reset after adjustment"
        );
        assertEq(
            stateAfterAdjustment.globalPositions.marginDepositedTotal,
            uint256(
                int256(stateBeforeAdjustment.globalPositions.marginDepositedTotal) +
                    stateBeforeAdjustment.marketSummary.profitLossTotalByLongs +
                    stateBeforeAdjustment.marketSummary.accruedFundingTotalByLongs -
                    1e18 -
                    int256(mockKeeperFee.getKeeperFee())
            ),
            "Global margin deposited should have been set to global margin after settlement + margin adjustment"
        );
        assertEq(
            stateAfterAdjustment.collateralPerShare,
            stateBeforeAdjustment.collateralPerShare,
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

        StateBefore memory stateBeforeAdjustment = StateBefore({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

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

        StateAfter memory stateAfterAdjustment = StateAfter({
            position: vaultProxy.getPosition(tokenId),
            positionSummary: leverageModProxy.getPositionSummary(tokenId),
            marketSummary: leverageModProxy.getMarketSummary(),
            globalPositions: vaultProxy.getGlobalPositions(),
            collateralPerShare: stableModProxy.stableCollateralPerShare()
        });

        assertEq(
            stateAfterAdjustment.position.lastPrice,
            newCollateralPrice * 1e10,
            "Last price should have been reset to current price"
        );
        assertEq(
            stateAfterAdjustment.position.marginDeposited,
            uint256(
                stateBeforeAdjustment.positionSummary.marginAfterSettlement -
                    int256(mockKeeperFee.getKeeperFee()) -
                    int256(adjustmentTradeFee)
            ),
            "Margin is not correct after adjustment"
        );
        assertEq(
            stateAfterAdjustment.position.additionalSize,
            stateBeforeAdjustment.position.additionalSize - 10e18,
            "Size is not correct after adjustment"
        );
        assertEq(stateAfterAdjustment.positionSummary.profitLoss, 0, "PnL should have been settled after adjustment");
        assertEq(
            stateAfterAdjustment.marketSummary.profitLossTotalByLongs,
            0,
            "Total PnL should have been reset after adjustment"
        );
        assertEq(
            stateAfterAdjustment.globalPositions.marginDepositedTotal,
            uint256(
                int256(stateBeforeAdjustment.globalPositions.marginDepositedTotal) +
                    stateBeforeAdjustment.marketSummary.profitLossTotalByLongs +
                    stateBeforeAdjustment.marketSummary.accruedFundingTotalByLongs -
                    int256(mockKeeperFee.getKeeperFee()) -
                    int256(adjustmentTradeFee)
            ),
            "Global margin deposited should have been set to global margin after settlement + margin adjustment"
        );
        assertGt(
            stateAfterAdjustment.collateralPerShare,
            stateBeforeAdjustment.collateralPerShare,
            "Collateral per share should increase after adjustment because of trade fee"
        );
    }
}
