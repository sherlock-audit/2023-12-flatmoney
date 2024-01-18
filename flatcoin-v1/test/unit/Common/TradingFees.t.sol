// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {OrderHelpers} from "../../helpers/OrderHelpers.sol";
import {FlatcoinStructs} from "src/libraries/FlatcoinStructs.sol";

import "forge-std/console2.sol";

contract WithdrawAndLeverageFeeTest is Setup, OrderHelpers {
    uint256 stableWithdrawFee = 0.005e18; // 0.5%
    uint256 levTradingFee = 0.001e18; // 0.1%

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);

        stableModProxy.setStableWithdrawFee(stableWithdrawFee);
        leverageModProxy.setLevTradingFee(levTradingFee);
    }

    function test_deposits_and_withdrawal_fees() public {
        uint256 keeperFee = mockKeeperFee.getKeeperFee();
        uint256 aliceWethBalanceBefore = WETH.balanceOf(alice);

        // First deposit mint doesn't use offchain oracle price
        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 2000e8,
            keeperFeeAmount: keeperFee
        });

        // Uses offchain oracle price on deposit to mint deposit tokens
        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 2000e8,
            keeperFeeAmount: keeperFee
        });

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 200e18,
            oraclePrice: 2000e8,
            keeperFeeAmount: keeperFee
        });

        // Withdraw 25%
        uint256 amount = 100e18;
        announceAndExecuteWithdraw({
            traderAccount: alice,
            keeperAccount: keeper,
            withdrawAmount: amount,
            oraclePrice: 2000e8,
            keeperFeeAmount: keeperFee
        });
        uint256 aliceWethBalance = WETH.balanceOf(alice);
        uint256 stableCollateralPerShare = stableModProxy.stableCollateralPerShare();

        assertEq(
            aliceWethBalanceBefore,
            WETH.balanceOf(alice) + (keeperFee * 4) + 300e18 + ((100e18 * stableWithdrawFee) / 1e18),
            "Alice didn't get the right amount of WETH back after 25% withdraw"
        );
        assertEq(vaultProxy.stableCollateralTotal(), 300.5e18, "Incorrect stable collateral total after 25% withdraw");

        // Withdraw another 25%
        announceAndExecuteWithdraw({
            traderAccount: alice,
            keeperAccount: keeper,
            withdrawAmount: amount,
            oraclePrice: 2000e8,
            keeperFeeAmount: keeperFee
        });

        assertApproxEqAbs( // check that Alice received the expected amount of WETH back
            WETH.balanceOf(alice),
            // Alice should receive WETH minus keeper fee and withdraw fee
            aliceWethBalance +
                ((stableCollateralPerShare * amount) / 1e18) -
                keeperFee -
                ((((stableCollateralPerShare * amount) / 1e18) * stableWithdrawFee) / 1e18), // withdraw fee
            1e6, // rounding
            "Alice didn't get the right amount of WETH back after second withdraw"
        );
        assertEq(WETH.balanceOf(address(delayedOrderProxy)), 0, "Delayed order should have 0 WETH");
        assertEq(
            aliceWethBalanceBefore,
            WETH.balanceOf(address(vaultProxy)) + WETH.balanceOf(address(alice)) + (keeperFee * 5),
            "Vault should have remaining WETH"
        );

        // Withdraw remainder
        announceAndExecuteWithdraw({
            traderAccount: alice,
            keeperAccount: keeper,
            withdrawAmount: amount * 2,
            oraclePrice: 2000e8,
            keeperFeeAmount: keeperFee
        });

        assertApproxEqAbs(
            aliceWethBalanceBefore,
            WETH.balanceOf(address(alice)) + (keeperFee * 6),
            1e6,
            "Alice should get all her WETH back"
        );
        assertApproxEqAbs(WETH.balanceOf(address(vaultProxy)), 0, 1e6, "Vault should have no WETH");
    }

    function test_deposit_and_leverage_fees() public {
        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;
        uint256 margin = 100e18;
        uint256 size = 100e18; // 2x

        uint256 keeperFee = mockKeeperFee.getKeeperFee();
        uint256 aliceWethBalanceBefore = WETH.balanceOf(alice);

        // First deposit mint doesn't use offchain oracle price
        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: 2000e8,
            keeperFeeAmount: keeperFee
        });

        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: margin,
            additionalSize: size,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        assertEq(
            stableModProxy.stableCollateralPerShare(),
            1e18 + ((size * levTradingFee) / stableModProxy.totalSupply()),
            "Stable collateral per share should be higher from leverage trade fee"
        );

        announceAndExecuteLeverageClose({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 aliceLPBalance = stableModProxy.balanceOf(alice);
        uint256 aliceWethBalanceBeforeWithdraw = WETH.balanceOf(alice);
        uint256 stableCollateralPerShare = stableModProxy.stableCollateralPerShare();

        assertEq(
            stableCollateralPerShare,
            1e18 + (((size * levTradingFee) / stableModProxy.totalSupply()) * 2),
            "Stable collateral per share should be higher from leverage 2 trade fees"
        );

        // Withdraw half the stable LP tokens
        announceAndExecuteWithdraw({
            traderAccount: alice,
            keeperAccount: keeper,
            withdrawAmount: aliceLPBalance / 2,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        assertEq(
            aliceWethBalanceBeforeWithdraw,
            WETH.balanceOf(alice) -
                (((aliceLPBalance / 2) * stableCollateralPerShare) / 1e18) +
                keeperFee +
                (((((aliceLPBalance / 2) * stableCollateralPerShare) / 1e18) * stableWithdrawFee) / 1e18), // account for the stable withdraw fee
            "Incorrect WETH balance after withdraw"
        );

        aliceLPBalance = stableModProxy.balanceOf(alice);
        aliceWethBalanceBeforeWithdraw = WETH.balanceOf(alice);
        stableCollateralPerShare = stableModProxy.stableCollateralPerShare();

        // Withdraw the remaining stable LP tokens
        announceAndExecuteWithdraw({
            traderAccount: alice,
            keeperAccount: keeper,
            withdrawAmount: aliceLPBalance,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        assertEq(
            aliceWethBalanceBeforeWithdraw,
            WETH.balanceOf(alice) - ((aliceLPBalance * stableCollateralPerShare) / 1e18) + keeperFee,
            "Incorrect WETH balance after withdraw"
        );
        assertEq(stableModProxy.totalSupply(), 0, "Should be 0 totalSupply");
        assertEq(
            stableModProxy.stableCollateralPerShare(),
            1e18,
            "Stable collateral per share should be reset to 1e18"
        );
        assertEq(WETH.balanceOf(alice) + (keeperFee * 5), aliceWethBalanceBefore, "Alice should get all her WETH back");
        assertEq(WETH.balanceOf(address(vaultProxy)), 0, "There should be no stable collateral in vault");
        assertEq(vaultProxy.stableCollateralTotal(), 0, "There should be no stable collateral accounted for in vault");
    }
}
