// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {OrderHelpers} from "../../helpers/OrderHelpers.sol";
import {OpenPositionTest} from "../Leverage-Module/OpenPosition.t.sol";
import "forge-std/console2.sol";

import "../../../src/interfaces/IChainlinkAggregatorV3.sol";

contract WithdrawTest is Setup, OrderHelpers, OpenPositionTest {
    function test_withdraw() public {
        vm.startPrank(alice);

        uint256 stableDeposit = 100e18;
        uint256 aliceBalanceBefore = WETH.balanceOf(alice);

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        // Withdraw 50%
        uint256 aliceBalance = stableModProxy.balanceOf(alice);
        announceAndExecuteWithdraw({
            traderAccount: alice,
            keeperAccount: keeper,
            withdrawAmount: aliceBalance / 2,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        assertApproxEqAbs(
            WETH.balanceOf(alice),
            aliceBalanceBefore - (stableDeposit / 2) - (mockKeeperFee.getKeeperFee() * 2),
            0.0000001e18,
            "Alice's balance after half withdrawal incorrect"
        );
        assertEq(stableModProxy.balanceOf(alice), stableDeposit / 2, "Alice's flatcoin balance incorrect");

        // Withdraw the second 50%
        // Have Bob deposit some amount first so that Alice's full withdrawal doesn't revert on minimum liquidity
        announceAndExecuteDeposit({
            traderAccount: bob,
            keeperAccount: keeper,
            depositAmount: 1e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        aliceBalance = stableModProxy.balanceOf(alice);
        announceAndExecuteWithdraw({
            traderAccount: alice,
            keeperAccount: keeper,
            withdrawAmount: aliceBalance,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        assertApproxEqAbs(
            WETH.balanceOf(alice),
            aliceBalanceBefore - (mockKeeperFee.getKeeperFee() * 3),
            0.0000001e18,
            "Alice's balance after full withdrawal incorrect"
        );
        assertEq(stableModProxy.balanceOf(alice), 0, "Alice's flatcoin balance should be 0");
    }

    function test_open_position_withdraw_no_skew() public {
        vm.startPrank(admin);
        vaultProxy.setSkewFractionMax(10_000e18);

        uint256 stableDeposit = 100e18;
        uint256 aliceBalanceBefore = WETH.balanceOf(alice);

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });
        // 100 ETH collateral, 100 ETH additional size (2x leverage)
        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 100e18,
            additionalSize: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        uint256 stableCollateralPerShareBefore = stableModProxy.stableCollateralPerShare();
        uint256 wethBalanceOfVaultBefore = WETH.balanceOf(address(vaultProxy));

        uint256 stableBalanceOf = stableModProxy.balanceOf(alice);
        uint256 withdrawAmount = stableBalanceOf / 2;

        announceAndExecuteWithdraw({
            traderAccount: alice,
            keeperAccount: keeper,
            withdrawAmount: withdrawAmount,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        uint256 stableCollateralPerShareAfter = stableModProxy.stableCollateralPerShare();
        uint256 wethBalanceOfVaultAfter = WETH.balanceOf(address(vaultProxy));

        assertLt(wethBalanceOfVaultAfter, wethBalanceOfVaultBefore);
        assertEq(
            wethBalanceOfVaultBefore,
            wethBalanceOfVaultAfter + ((withdrawAmount * stableCollateralPerShareAfter) / 1e18)
        );

        // Alice's balance should be returned correctly discounting for the margin.
        assertApproxEqAbs(
            WETH.balanceOf(alice),
            aliceBalanceBefore - (stableDeposit / 2) - (mockKeeperFee.getKeeperFee() * 3) - 100e18,
            0.0000001e18,
            "Alice's balance after half withdrawal incorrect"
        );
        assertApproxEqAbs(stableCollateralPerShareBefore, stableCollateralPerShareAfter, 1);
    }

    function test_open_position_withdraw_long_skew() public {
        vm.startPrank(admin);
        vaultProxy.setSkewFractionMax(10_000e18);

        uint256 stableDeposit = 100e18;
        uint256 aliceBalanceBefore = WETH.balanceOf(alice);

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });
        // 120 ETH collateral, 120 ETH additional size (2x leverage)
        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 120e18,
            additionalSize: 120e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        uint256 stableCollateralPerShareBefore = stableModProxy.stableCollateralPerShare();
        uint256 wethBalanceOfVaultBefore = WETH.balanceOf(address(vaultProxy));

        uint256 stableBalanceOf = stableModProxy.balanceOf(alice);
        uint256 withdrawAmount = stableBalanceOf / 2;

        announceAndExecuteWithdraw({
            traderAccount: alice,
            keeperAccount: keeper,
            withdrawAmount: withdrawAmount,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        uint256 stableCollateralPerShareAfter = stableModProxy.stableCollateralPerShare();
        uint256 wethBalanceOfVaultAfter = WETH.balanceOf(address(vaultProxy));

        assertLt(wethBalanceOfVaultAfter, wethBalanceOfVaultBefore);
        assertEq(
            wethBalanceOfVaultBefore,
            wethBalanceOfVaultAfter + ((withdrawAmount * stableCollateralPerShareAfter) / 1e18)
        );
        // Alice's balance should be returned correctly discounting for the margin.
        assertApproxEqAbs(
            WETH.balanceOf(alice),
            aliceBalanceBefore - (stableDeposit / 2) - (mockKeeperFee.getKeeperFee() * 3) - 120e18,
            0.0000001e18,
            "Alice's balance after half withdrawal incorrect"
        );
        assertApproxEqAbs(stableCollateralPerShareBefore, stableCollateralPerShareAfter, 1);
    }

    function test_open_position_withdraw_stable_skew() public {
        vm.startPrank(admin);
        vaultProxy.setSkewFractionMax(10_000e18);

        uint256 stableDeposit = 100e18;
        uint256 aliceBalanceBefore = WETH.balanceOf(alice);

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });
        // 80 ETH collateral, 80 ETH additional size (2x leverage)
        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 80e18,
            additionalSize: 80e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        uint256 stableCollateralPerShareBefore = stableModProxy.stableCollateralPerShare();
        uint256 wethBalanceOfVaultBefore = WETH.balanceOf(address(vaultProxy));

        uint256 stableBalanceOf = stableModProxy.balanceOf(alice);
        uint256 withdrawAmount = stableBalanceOf / 2;

        announceAndExecuteWithdraw({
            traderAccount: alice,
            keeperAccount: keeper,
            withdrawAmount: withdrawAmount,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        uint256 stableCollateralPerShareAfter = stableModProxy.stableCollateralPerShare();
        uint256 wethBalanceOfVaultAfter = WETH.balanceOf(address(vaultProxy));

        assertLt(wethBalanceOfVaultAfter, wethBalanceOfVaultBefore);
        assertEq(
            wethBalanceOfVaultBefore,
            wethBalanceOfVaultAfter + ((withdrawAmount * stableCollateralPerShareAfter) / 1e18)
        );
        // Alice's balance should be returned correctly discounting for the margin.
        assertApproxEqAbs(
            WETH.balanceOf(alice),
            aliceBalanceBefore - (stableDeposit / 2) - (mockKeeperFee.getKeeperFee() * 3) - 80e18,
            0.0000001e18,
            "Alice's balance after half withdrawal incorrect"
        );
        assertApproxEqAbs(stableCollateralPerShareBefore, stableCollateralPerShareAfter, 1);
    }
}
