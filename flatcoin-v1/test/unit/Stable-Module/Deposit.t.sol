// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {OrderHelpers} from "../../helpers/OrderHelpers.sol";
import "forge-std/console2.sol";

import "../../../src/interfaces/IChainlinkAggregatorV3.sol";

contract DepositTest is Setup, OrderHelpers {
    function test_two_deposits() public {
        vm.startPrank(alice);

        uint256 aliceBalanceBefore = WETH.balanceOf(alice);
        uint256 stableCollateralPerShareBefore = stableModProxy.stableCollateralPerShare();
        uint256 depositAmount = 100e18;
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: depositAmount,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        assertEq(WETH.balanceOf(alice), aliceBalanceBefore - depositAmount - mockKeeperFee.getKeeperFee());
        assertEq(stableModProxy.balanceOf(alice), depositAmount);

        uint256 newDepositAmount = 100e18;
        // Deposit more into the StableModule.
        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: newDepositAmount,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 stableCollateralPerShareAfter = stableModProxy.stableCollateralPerShare();

        assertEq(stableCollateralPerShareBefore, stableCollateralPerShareAfter);
        assertEq(
            WETH.balanceOf(alice),
            aliceBalanceBefore - depositAmount - newDepositAmount - mockKeeperFee.getKeeperFee() * 2,
            "Alice's balance incorrect after all deposits"
        );
        assertEq(stableModProxy.balanceOf(alice), depositAmount + newDepositAmount);
    }

    function test_two_deposits_price_increase() public {
        vm.startPrank(alice);

        uint256 aliceBalanceBefore = WETH.balanceOf(alice);
        uint256 stableCollateralPerShareBefore = stableModProxy.stableCollateralPerShare();
        uint256 collateralPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        assertEq(WETH.balanceOf(alice), aliceBalanceBefore - 100e18 - mockKeeperFee.getKeeperFee());
        assertEq(stableModProxy.balanceOf(alice), 100e18);

        // Increase WETH Chainlink price to $2k (2x)
        uint256 newCollateralPrice = 2000e8;
        setWethPrice(newCollateralPrice);

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: newCollateralPrice,
            keeperFeeAmount: 0
        });

        uint256 stableCollateralPerShareAfter = stableModProxy.stableCollateralPerShare();

        assertEq(stableCollateralPerShareBefore, stableCollateralPerShareAfter);
        assertEq(
            WETH.balanceOf(alice),
            aliceBalanceBefore - 200e18 - (mockKeeperFee.getKeeperFee() * 2),
            "Alice's balance is incorrect after all deposits"
        );
        assertEq(stableModProxy.balanceOf(alice), 200e18);
    }
}
