// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import "forge-std/console2.sol";

import {Setup} from "../../helpers/Setup.sol";
import {DecimalMath} from "../../../src/libraries/DecimalMath.sol";
import {FlatcoinErrors} from "../../../src/libraries/FlatcoinErrors.sol";
import "../../helpers/OrderHelpers.sol";

contract LiquidateTest is Setup, OrderHelpers {
    using DecimalMath for int256;

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);

        vaultProxy.setMaxFundingVelocity(0.003e18);

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

    function test_liquidation_when_price_decrease_but_position_not_liquidatable() public {
        vm.startPrank(alice);

        setWethPrice(1000e8);

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        // Alice opens a position with 50 WETH margin and 3x leverage.
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 50e18,
            additionalSize: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        skip(2 days);

        uint256 liqPrice = liquidationModProxy.liquidationPrice(0);

        // Price goes down to within $10 of the liquidation price.
        setWethPrice((liqPrice + 10e18) / 1e10);

        assertFalse(liquidationModProxy.canLiquidate(0), "Leverage position should not be liquidatable");

        vm.startPrank(liquidator);
        vm.expectRevert(abi.encodeWithSelector(FlatcoinErrors.CannotLiquidate.selector, tokenId));

        liquidationModProxy.liquidate(tokenId);
    }

    function test_liquidation_when_price_decrease_but_position_not_liquidatable_due_to_funding() public {
        vm.startPrank(alice);

        setWethPrice(1000e8);

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        // Alice opens a position with 50 WETH margin and 2x leverage.
        // The market is skewed towards LP.
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 50e18,
            additionalSize: 50e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        uint256 liqPriceBefore = liquidationModProxy.liquidationPrice(0);

        skip(15 days);

        uint256 liqPriceAfter = liquidationModProxy.liquidationPrice(0);

        assertLt(liqPriceAfter, liqPriceBefore, "Liquidation price should have decreased");

        // Set the price of WETH  to be the earlier liquidation price.
        setWethPrice(liqPriceBefore / 1e10);

        assertFalse(liquidationModProxy.canLiquidate(0), "Leverage position should not be liquidatable");

        vm.startPrank(liquidator);
        vm.expectRevert(abi.encodeWithSelector(FlatcoinErrors.CannotLiquidate.selector, tokenId));

        liquidationModProxy.liquidate(tokenId);
    }

    function test_liquidation_when_price_increases_and_position_not_liquidatable() public {
        vm.startPrank(alice);

        setWethPrice(1000e8);

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        // Alice opens a position with 50 WETH margin and 3x leverage.
        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 50e18,
            additionalSize: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        skip(2 days);

        // Price goes up by 20%.
        setWethPrice(1200e8);

        assertFalse(liquidationModProxy.canLiquidate(0), "Leverage position should not be liquidatable");

        vm.startPrank(liquidator);
        vm.expectRevert(abi.encodeWithSelector(FlatcoinErrors.CannotLiquidate.selector, tokenId));

        liquidationModProxy.liquidate(tokenId);
    }

    // The test checks that funding rates are taken into account when checking if a position is liquidatable or not.
    function test_liquidation_when_price_increase_but_position_liquidatable_due_to_funding() public {
        setWethPrice(1000e8);

        uint256 tokenId = announceAndExecuteDepositAndLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            margin: 60e18,
            additionalSize: 120e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        vm.startPrank(admin);
        vaultProxy.setMaxFundingVelocity(0.006e18);
        vaultProxy.setMaxVelocitySkew(0.2e18);

        // Note that the amount of days to be skipped has been chosen arbitrarily.
        // The higher the number of days skipped, the higher the funding rate.
        // This means, in this particular scenario, longs are paying LPs so much so that their
        // profits are offset by the funding fees.
        skip(15 days);

        uint256 liqPrice = liquidationModProxy.liquidationPrice(tokenId);

        assertGt(liqPrice / 1e10, 1000e8, "Liquidation price should be greater than entry price");

        // Note: We are taking a margin of error here of $1 because of the approximation issues in the liquidation price.
        setWethPrice((liqPrice - 1e18) / 1e10);

        assertTrue(liquidationModProxy.canLiquidate(0), "Leverage position should be liquidatable");

        uint256 liquidatorBalanceBefore = WETH.balanceOf(liquidator);
        uint256 stableCollateralTotalBefore = vaultProxy.stableCollateralTotal();

        FlatcoinStructs.MarketSummary memory marketSummary = leverageModProxy.getMarketSummary();
        FlatcoinStructs.PositionSummary memory alicePositionSummary = leverageModProxy.getPositionSummary(tokenId);
        uint256 liquidationFee = liquidationModProxy.getLiquidationFee(tokenId);

        vm.startPrank(liquidator);
        liquidationModProxy.liquidate(tokenId);

        uint256 liquidatorBalanceAfter = WETH.balanceOf(liquidator);
        uint256 stableCollateralTotalAfter = vaultProxy.stableCollateralTotal();
        uint256 remainingMargin = (uint256(alicePositionSummary.marginAfterSettlement) > liquidationFee)
            ? uint256(alicePositionSummary.marginAfterSettlement) - liquidationFee
            : 0;

        assertEq(
            liquidatorBalanceAfter - liquidatorBalanceBefore,
            liquidationFee,
            "Liquidator fee not awarded correctly"
        );

        // Note that we are subtracting the funding fees from the remaining margin on the RHS because a call to `liquidate`
        // function will settle the funding fees before actually liquidating a position.
        // Why subtract instead of add? This is because the funding fees are negative in this case indicating that
        // the longs are paying the LPs (so -ve of -ve is +ve). After settlement, the LPs will receive this amount.
        assertEq(
            int256(stableCollateralTotalAfter) - int256(stableCollateralTotalBefore),
            int256(remainingMargin) - alicePositionSummary.profitLoss - marketSummary.accruedFundingTotalByLongs,
            "Alice's remaining margin should be given to the LPs"
        );

        // The position should not exist in the `_positions` mapping.
        assertTrue(vaultProxy.getPosition(tokenId).marginDeposited == 0, "Position not deleted");

        FlatcoinStructs.VaultSummary memory vaultSummary = vaultProxy.getVaultSummary();

        assertEq(
            stableCollateralTotalAfter + vaultSummary.globalPositions.marginDepositedTotal,
            WETH.balanceOf(address(vaultProxy)),
            "Vault balance incorrect"
        );
    }

    /// @notice Tests accounting when the liquidator fee is lower than usual because the position is close to the liquidation price.
    function test_liquidation_lower_liquidator_fee() public {
        setWethPrice(1000e8);

        uint256 tokenId = announceAndExecuteDepositAndLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            margin: 50e18,
            additionalSize: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        skip(2 days);

        uint256 liqPrice = liquidationModProxy.liquidationPrice(tokenId);

        setWethPrice((liqPrice - 2.1e18) / 1e10); // liquidator fee will be lower than regular fee

        assertTrue(liquidationModProxy.canLiquidate(0), "Leverage position should be liquidatable");

        uint256 liquidatorBalanceBefore = WETH.balanceOf(liquidator);
        uint256 stableCollateralTotalBefore = vaultProxy.stableCollateralTotal();

        FlatcoinStructs.PositionSummary memory alicePositionSummary = leverageModProxy.getPositionSummary(tokenId);
        int256 remainingMargin = alicePositionSummary.marginAfterSettlement;
        int256 profitLoss = alicePositionSummary.profitLoss;

        vm.startPrank(liquidator);
        liquidationModProxy.liquidate(tokenId); // should pass invariant checks

        uint256 liquidatorBalanceAfter = WETH.balanceOf(liquidator);
        uint256 stableCollateralTotalAfter = vaultProxy.stableCollateralTotal();
        uint256 liquidatorFee = liquidatorBalanceAfter - liquidatorBalanceBefore;

        assertGt(liquidatorFee, 0, "Liquidator fee should have been awarded");
        assertEq(int256(liquidatorFee), remainingMargin, "Liquidator fee should be the same as margin");
        assertEq(vaultProxy.getPosition(tokenId).marginDeposited, 0, "Position should have been deleted");
        assertEq(
            int256(stableCollateralTotalBefore),
            int256(stableCollateralTotalAfter) + profitLoss,
            "Incorrect stable collateral total"
        );
    }

    // Test to check that liquidations are working as expected even in the case of a position
    // being underwater (bad debt).
    function test_liquidation_when_position_underwater_due_to_price_decrease() public {
        setWethPrice(1000e8);

        uint256 tokenId = announceAndExecuteDepositAndLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            margin: 50e18,
            additionalSize: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        skip(2 days);

        uint256 liqPrice = liquidationModProxy.liquidationPrice(tokenId);

        setWethPrice((liqPrice - 50e18) / 1e10);

        assertTrue(liquidationModProxy.canLiquidate(0), "Leverage position should be liquidatable");

        uint256 liquidatorBalanceBefore = WETH.balanceOf(liquidator);
        uint256 stableCollateralTotalBefore = vaultProxy.stableCollateralTotal();

        FlatcoinStructs.PositionSummary memory alicePositionSummary = leverageModProxy.getPositionSummary(tokenId);

        assertLt(alicePositionSummary.marginAfterSettlement, 0, "Position should be underwater");

        vm.startPrank(liquidator);
        liquidationModProxy.liquidate(tokenId);

        uint256 liquidatorBalanceAfter = WETH.balanceOf(liquidator);
        uint256 stableCollateralTotalAfter = vaultProxy.stableCollateralTotal();

        assertEq(liquidatorBalanceAfter, liquidatorBalanceBefore, "Liquidator fee should not have been awarded");

        // Note that funding fees play no role here as the market was perfectly hedged.
        assertEq(
            int256(stableCollateralTotalAfter) - int256(stableCollateralTotalBefore),
            alicePositionSummary.marginAfterSettlement - alicePositionSummary.profitLoss,
            "Stable collateral total after liquidation incorrect"
        );

        assertEq(vaultProxy.getPosition(tokenId).marginDeposited, 0, "Position should have been deleted");

        FlatcoinStructs.VaultSummary memory vaultSummary = vaultProxy.getVaultSummary();

        // Total ETH in the vault is the sum of the stable collateral and the margin deposited.
        // Note that we are not adding or subtracting the funding fees given that settlement of the same
        // is accounted for already in the `stableCollateralTotal` or `marginDepositedTotal` variables
        // in the `settleFundingFees` function in the vault contract.
        assertEq(
            stableCollateralTotalAfter + vaultSummary.globalPositions.marginDepositedTotal,
            WETH.balanceOf(address(vaultProxy)),
            "Vault balance incorrect"
        );
    }

    // Test to check that liquidations are working as expected even in the case of a position
    // being underwater (bad debt).
    function test_liquidation_when_position_underwater_due_to_funding_fees_payment() public {
        setWethPrice(1000e8);

        uint256 tokenId = announceAndExecuteDepositAndLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            margin: 60e18,
            additionalSize: 120e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        vm.startPrank(admin);
        vaultProxy.setMaxFundingVelocity(0.006e18);
        vaultProxy.setMaxVelocitySkew(0.2e18);

        // Note that the amount of days to be skipped has been chosen arbitrarily.
        skip(15 days);

        uint256 liqPrice = liquidationModProxy.liquidationPrice(tokenId);

        setWethPrice((liqPrice - 50e18) / 1e10);

        assertTrue(liquidationModProxy.canLiquidate(0), "Leverage position should be liquidatable");

        uint256 liquidatorBalanceBefore = WETH.balanceOf(liquidator);
        uint256 stableCollateralTotalBefore = vaultProxy.stableCollateralTotal();

        FlatcoinStructs.MarketSummary memory marketSummary = leverageModProxy.getMarketSummary();
        FlatcoinStructs.PositionSummary memory alicePositionSummary = leverageModProxy.getPositionSummary(tokenId);

        assertLt(alicePositionSummary.marginAfterSettlement, 0, "Position should be underwater");

        vm.startPrank(liquidator);
        liquidationModProxy.liquidate(tokenId);

        uint256 liquidatorBalanceAfter = WETH.balanceOf(liquidator);
        uint256 stableCollateralTotalAfter = vaultProxy.stableCollateralTotal();

        assertEq(liquidatorBalanceAfter, liquidatorBalanceBefore, "Liquidator fee should not have been awarded");
        assertEq(
            int256(stableCollateralTotalAfter) - int256(stableCollateralTotalBefore),
            alicePositionSummary.marginAfterSettlement -
                alicePositionSummary.profitLoss -
                marketSummary.accruedFundingTotalByLongs,
            "Stable collateral total after liquidation incorrect"
        );

        assertEq(vaultProxy.getPosition(tokenId).marginDeposited, 0, "Position should have been deleted");

        FlatcoinStructs.VaultSummary memory vaultSummary = vaultProxy.getVaultSummary();

        // Total ETH in the vault is the sum of the stable collateral and the margin deposited.
        // Note that we are not adding or subtracting the funding fees given that settlement of the same
        // is accounted for already in the `stableCollateralTotal` or `marginDepositedTotal` variables
        // in the `settleFundingFees` function in the vault contract.
        assertEq(
            stableCollateralTotalAfter + vaultSummary.globalPositions.marginDepositedTotal,
            WETH.balanceOf(address(vaultProxy)),
            "Vault balance incorrect"
        );
    }

    function test_liquidation_using_price_update_data() public {
        setWethPrice(1000e8);

        uint256 tokenId = announceAndExecuteDepositAndLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            margin: 50e18,
            additionalSize: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        skip(2 days);

        uint256 liqPrice = liquidationModProxy.liquidationPrice(0);

        // Note: We are taking a margin of error here of $1 because of the approximation issues in the liquidation price.
        setWethPrice((liqPrice - 1e18) / 1e10);

        assertTrue(liquidationModProxy.canLiquidate(0), "Leverage position should be liquidatable");

        uint256 liquidatorBalanceBefore = WETH.balanceOf(liquidator);
        uint256 stableCollateralTotalBefore = vaultProxy.stableCollateralTotal();

        FlatcoinStructs.PositionSummary memory alicePositionSummary = leverageModProxy.getPositionSummary(tokenId);
        uint256 liquidationFee = liquidationModProxy.getLiquidationFee(tokenId);

        vm.startPrank(liquidator);
        // Since the next function call updates Pyth price, we need to skip at least 1 second
        // for it to be updated.
        skip(1);
        // Should not be liquidatable (just above liquidation price)
        bytes[] memory priceUpdateData = getPriceUpdateData((liqPrice + 1e18) / 1e10);
        vm.expectRevert(abi.encodeWithSelector(FlatcoinErrors.CannotLiquidate.selector, tokenId));
        liquidationModProxy.liquidate{value: 2}(tokenId, priceUpdateData);

        // Should be liquidatable (just below liquidation price)
        skip(1);
        liquidationModProxy.liquidate{value: 2}(tokenId, getPriceUpdateData((liqPrice - 1e18) / 1e10));

        uint256 liquidatorBalanceAfter = WETH.balanceOf(liquidator);
        uint256 stableCollateralTotalAfter = vaultProxy.stableCollateralTotal();
        uint256 remainingMargin = (uint256(alicePositionSummary.marginAfterSettlement) > liquidationFee)
            ? uint256(alicePositionSummary.marginAfterSettlement) - liquidationFee
            : 0;

        assertEq(
            liquidatorBalanceAfter - liquidatorBalanceBefore,
            liquidationFee,
            "Liquidator fee not awarded correctly"
        );

        FlatcoinStructs.VaultSummary memory vaultSummary = vaultProxy.getVaultSummary();

        assertEq(
            stableCollateralTotalAfter + vaultSummary.globalPositions.marginDepositedTotal,
            WETH.balanceOf(address(vaultProxy)),
            "Vault balance incorrect"
        );

        // Note: We are not taking into account the settled funding fees as this test won't produce any.
        assertEq(
            int256(stableCollateralTotalAfter) - int256(stableCollateralTotalBefore),
            int256(remainingMargin) - alicePositionSummary.profitLoss,
            "Alice's remaining margin should be given to the LPs"
        );

        // The position should not exist in the `_positions` mapping.
        assertTrue(vaultProxy.getPosition(tokenId).marginDeposited == 0, "Position not deleted");
    }

    function test_liquidate_when_liquidationFee_within_bounds() public {
        setWethPrice(1000e8);

        // Increase fee bound for more accurate liquidation price approximation.
        liquidationModProxy.setLiquidationFeeBounds({
            _newLiquidationFeeLowerBound: 4e18,
            _newLiquidationFeeUpperBound: 10_000e18
        });

        uint256 tokenId = announceAndExecuteDepositAndLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            margin: 50e18,
            additionalSize: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        skip(2 days);

        uint256 liqPrice = liquidationModProxy.liquidationPrice(0);

        // Check the liquidation price precisely in this test
        // By setting the price just above liquidation price, the position should not be liquidatable.
        setWethPrice((liqPrice + 1e10) / 1e10);
        assertFalse(liquidationModProxy.canLiquidate(tokenId), "Leverage position should not be liquidatable");

        vm.expectRevert(abi.encodeWithSelector(FlatcoinErrors.CannotLiquidate.selector, tokenId));
        liquidationModProxy.liquidate(tokenId);

        // By setting the price just below liquidation price, the position should be liquidatable.
        setWethPrice((liqPrice - 1e10) / 1e10);
        assertTrue(liquidationModProxy.canLiquidate(tokenId), "Leverage position should be liquidatable");

        uint256 liquidatorBalanceBefore = WETH.balanceOf(liquidator);
        uint256 stableCollateralTotalBefore = vaultProxy.stableCollateralTotal();

        FlatcoinStructs.PositionSummary memory alicePositionSummary = leverageModProxy.getPositionSummary(tokenId);
        uint256 liquidationFee = liquidationModProxy.getLiquidationFee(tokenId);

        vm.startPrank(liquidator);
        liquidationModProxy.liquidate(tokenId);

        uint256 liquidatorBalanceAfter = WETH.balanceOf(liquidator);
        uint256 stableCollateralTotalAfter = vaultProxy.stableCollateralTotal();
        uint256 remainingMargin = (uint256(alicePositionSummary.marginAfterSettlement) > liquidationFee)
            ? uint256(alicePositionSummary.marginAfterSettlement) - liquidationFee
            : 0;

        assertEq(
            liquidatorBalanceAfter - liquidatorBalanceBefore,
            liquidationFee,
            "Liquidator fee not awarded correctly"
        );

        FlatcoinStructs.VaultSummary memory vaultSummary = vaultProxy.getVaultSummary();

        assertEq(
            stableCollateralTotalAfter + vaultSummary.globalPositions.marginDepositedTotal,
            WETH.balanceOf(address(vaultProxy)),
            "Vault balance incorrect"
        );

        // Note: We are not taking into account the settled funding fees as this test won't produce any.
        assertEq(
            int256(stableCollateralTotalAfter) - int256(stableCollateralTotalBefore),
            int256(remainingMargin) - alicePositionSummary.profitLoss,
            "Alice's remaining margin should be given to the LPs"
        );

        // The position should not exist in the `_positions` mapping.
        assertTrue(vaultProxy.getPosition(tokenId).marginDeposited == 0, "Position not deleted");
    }

    function test_liquidate_when_token_locked() public {
        setWethPrice(1000e8);

        uint256 tokenId = announceAndExecuteDepositAndLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        announceCloseLeverage({traderAccount: alice, tokenId: tokenId, keeperFeeAmount: 0});

        setWethPrice(750e8);

        vm.startPrank(liquidator);
        liquidationModProxy.liquidate(tokenId);
    }
}
