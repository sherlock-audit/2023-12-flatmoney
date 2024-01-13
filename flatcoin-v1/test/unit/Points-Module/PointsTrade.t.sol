// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {TransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Setup} from "../../helpers/Setup.sol";
import {OrderHelpers} from "../../helpers/OrderHelpers.sol";
import {ExpectRevert} from "../../helpers/ExpectRevert.sol";
import {PointsModule} from "src/PointsModule.sol";
import {FlatcoinModuleKeys} from "src/libraries/FlatcoinModuleKeys.sol";
import {FlatcoinStructs} from "src/libraries/FlatcoinStructs.sol";
import {FlatcoinErrors} from "src/libraries/FlatcoinErrors.sol";
import {IPointsModule} from "src/interfaces/IPointsModule.sol";

import "forge-std/console2.sol";

contract PointsTradeTest is Setup, OrderHelpers, ExpectRevert {
    function test_points_received_on_stable_deposit() public {
        uint256 depositAmount = 100e18;

        vm.startPrank(alice);

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: depositAmount,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });

        uint256 alicePointsBalance = pointsModProxy.balanceOf(alice);
        assertEq(alicePointsBalance, 100 * depositAmount);
        assertEq(pointsModProxy.totalSupply(), alicePointsBalance);
        assertEq(pointsModProxy.lockedBalance(alice), alicePointsBalance);
        assertEq(pointsModProxy.unlockTime(alice), block.timestamp + 365 days);
        assertEq(pointsModProxy.getUnlockTax(alice), 1e18);
    }

    function test_points_received_on_leverage_open() public {
        uint256 depositAmount = 100e18;
        uint256 margin = 50e18;
        uint256 size = 50e18;

        vm.startPrank(alice);

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: depositAmount,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });

        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: bob,
            keeperAccount: keeper,
            margin: margin,
            additionalSize: size,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });
        uint256 alicePointsBalance = pointsModProxy.balanceOf(alice);
        uint256 bobPointsBalance = pointsModProxy.balanceOf(bob);

        assertEq(bobPointsBalance, 200 * size);
        assertEq(pointsModProxy.totalSupply(), alicePointsBalance + bobPointsBalance);
        assertEq(pointsModProxy.lockedBalance(bob), bobPointsBalance);
        assertEq(pointsModProxy.unlockTime(bob), block.timestamp + 365 days);
        assertEq(pointsModProxy.getUnlockTax(bob), 1e18);

        announceAndExecuteLeverageClose({
            tokenId: tokenId,
            traderAccount: bob,
            keeperAccount: keeper,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });

        bobPointsBalance = pointsModProxy.balanceOf(bob);

        assertEq(bobPointsBalance, 200 * size); // no change
        assertEq(pointsModProxy.totalSupply(), alicePointsBalance + bobPointsBalance);
        assertEq(pointsModProxy.lockedBalance(bob), bobPointsBalance);
        assertLt(pointsModProxy.unlockTime(bob), block.timestamp + 365 days); // "Lt" because some time has passed
        assertLt(pointsModProxy.getUnlockTax(bob), 1e18);
    }

    function test_points_received_adjust_size_increase() public {
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

        uint256 alicePointsBalanceBefore = pointsModProxy.balanceOf(alice);

        // +10 ETH size
        announceAndExecuteLeverageAdjust({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            marginAdjustment: 1e18, // random change to test no impact
            additionalSizeAdjustment: 10e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 alicePointsBalanceAfter = pointsModProxy.balanceOf(alice);

        // check points balance increase
        assertEq(alicePointsBalanceBefore, alicePointsBalanceAfter - (10e18 * 200));
    }

    function test_points_none_received_adjust_size_decrease() public {
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

        uint256 alicePointsBalanceBefore = pointsModProxy.balanceOf(alice);

        // -10 ETH size
        announceAndExecuteLeverageAdjust({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            marginAdjustment: -1e18, // random change to test no impact
            additionalSizeAdjustment: -10e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 alicePointsBalanceAfter = pointsModProxy.balanceOf(alice);

        // check points balance increase
        assertEq(alicePointsBalanceBefore, alicePointsBalanceAfter);
    }
}
