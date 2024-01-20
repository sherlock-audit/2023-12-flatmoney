// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {OrderHelpers} from "../../helpers/OrderHelpers.sol";
import "../../../src/interfaces/IChainlinkAggregatorV3.sol";

contract ClosePositionTest is Setup, OrderHelpers {
    function test_close_position_no_price_change() public {
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

        uint256 stableCollateralPerShareBefore = stableModProxy.stableCollateralPerShare();

        // Close first position
        announceAndExecuteLeverageClose({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 stableCollateralPerShareAfter1 = stableModProxy.stableCollateralPerShare();
        assertApproxEqAbs(
            stableCollateralPerShareBefore,
            stableCollateralPerShareAfter1,
            1e6, // rounding error only
            "stableCollateralPerShare should not change"
        );

        // Close second position
        announceAndExecuteLeverageClose({
            tokenId: tokenId2,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 stableCollateralPerShareAfter2 = stableModProxy.stableCollateralPerShare();
        assertApproxEqAbs(
            stableCollateralPerShareBefore,
            stableCollateralPerShareAfter2,
            1e6, // rounding error only
            "stableCollateralPerShare should not change"
        );
        assertEq(
            aliceBalanceBefore - mockKeeperFee.getKeeperFee() * 5,
            WETH.balanceOf(alice) + stableDeposit,
            "Alice collateral balance incorrect"
        );
    }

    function test_close_position_price_increase() public {
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
        uint256 tokenId0 = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // Mock WETH Chainlink price to $2000 (100% increase)
        uint256 newCollateralPrice = 2000e8;
        setWethPrice(newCollateralPrice);

        // 70 ETH collateral, 70 ETH additional size (2x leverage)
        uint256 tokenId1 = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 70e18,
            additionalSize: 70e18,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        // Close first position
        announceAndExecuteLeverageClose({
            tokenId: tokenId0,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        // Close second position
        announceAndExecuteLeverageClose({
            tokenId: tokenId1,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        assertGt(aliceBalanceBefore, WETH.balanceOf(alice), "Alice's WETH balance should decrease"); // Alice still has the stable LP deposit to withdraw

        // Withdraw stable deposit
        // Have Bob deposit some amount first so that Alice's full withdrawal doesn't revert on minimum liquidity
        announceAndExecuteDeposit({
            traderAccount: bob,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        announceAndExecuteWithdraw({
            traderAccount: alice,
            keeperAccount: keeper,
            withdrawAmount: stableModProxy.balanceOf(alice),
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        // TODO: Modify `deposit` and `withdraw` function to account for pnl settlement.
        assertEq(
            aliceBalanceBefore - mockKeeperFee.getKeeperFee() * 6,
            WETH.balanceOf(alice),
            "Alice should have her stable deposit back"
        );
    }

    function test_close_position_price_decrease() public {
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
        // 20 ETH collateral, 20 ETH additional size (2x leverage)
        uint256 tokenId0 = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 20e18,
            additionalSize: 20e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // Mock WETH Chainlink price to $900 (10% decrease)
        uint256 newCollateralPrice = 900e8;
        setWethPrice(newCollateralPrice);

        // 10 ETH collateral, 50 ETH additional size (6x leverage)
        uint256 tokenId1 = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 50e18,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        // Close first position
        announceAndExecuteLeverageClose({
            tokenId: tokenId0,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        // Close second position
        announceAndExecuteLeverageClose({
            tokenId: tokenId1,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        // Withdraw stable deposit
        // Have Bob deposit some amount first so that Alice's full withdrawal doesn't revert on minimum liquidity
        announceAndExecuteDeposit({
            traderAccount: bob,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        announceAndExecuteWithdraw({
            traderAccount: alice,
            keeperAccount: keeper,
            withdrawAmount: stableModProxy.balanceOf(alice),
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        assertGt(aliceBalanceBefore, WETH.balanceOf(alice), "Alice's WETH balance should increase"); // Alice still has the stable LP deposit to withdraw
        assertApproxEqAbs(
            aliceBalanceBefore - mockKeeperFee.getKeeperFee() * 6,
            WETH.balanceOf(alice),
            1e6,
            "Alice should get her deposit back"
        ); // allow for some small rounding error
    }
}
