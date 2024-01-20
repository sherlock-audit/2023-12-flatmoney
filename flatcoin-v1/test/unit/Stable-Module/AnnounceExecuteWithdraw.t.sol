// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {OrderHelpers} from "../../helpers/OrderHelpers.sol";
import {FlatcoinStructs} from "src/libraries/FlatcoinStructs.sol";

import "forge-std/console2.sol";

contract AnnounceExecuteWithdrawTest is Setup, OrderHelpers {
    function test_deposits_and_withdrawal() public {
        vm.startPrank(admin);
        stableModProxy.setStableWithdrawFee(0);
        leverageModProxy.setLevTradingFee(0);

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

        // Withraw 25%
        announceAndExecuteWithdraw({
            traderAccount: alice,
            keeperAccount: keeper,
            withdrawAmount: 100e18,
            oraclePrice: 2000e8,
            keeperFeeAmount: keeperFee
        });

        // Withdraw the remaining 75%
        announceAndExecuteWithdraw({
            traderAccount: alice,
            keeperAccount: keeper,
            withdrawAmount: 300e18,
            oraclePrice: 2000e8,
            keeperFeeAmount: keeperFee
        });

        assertEq(aliceWethBalanceBefore, WETH.balanceOf(alice) + (keeperFee * 5), "Alice didn't get all her WETH back");
        assertEq(WETH.balanceOf(address(delayedOrderProxy)), 0, "Delayed order should have 0 WETH");
        assertEq(WETH.balanceOf(address(vaultProxy)), 0, "Vault should have 0 WETH");
        assertEq(stableModProxy.totalSupply(), 0, "Stable LP should have 0 supply");
    }
}
