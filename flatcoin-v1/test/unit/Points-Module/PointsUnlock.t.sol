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

contract PointsUnlockTest is Setup, OrderHelpers, ExpectRevert {
    function test_points_unlock_0() public {
        vm.startPrank(admin);

        PointsModule.MintPoints memory mintParams = PointsModule.MintPoints({to: alice, amount: 100e18});
        pointsModProxy.mintTo(mintParams);

        vm.startPrank(alice);

        assertEq(pointsModProxy.getUnlockTax(alice), 1e18);

        pointsModProxy.unlockAll();

        assertEq(pointsModProxy.balanceOf(alice), 0);
        assertEq(pointsModProxy.balanceOf(treasury), 100e18);
        assertEq(pointsModProxy.lockedBalance(alice), 0);
        assertEq(pointsModProxy.unlockTime(alice), 0);
        assertEq(pointsModProxy.getUnlockTax(alice), 0);
    }

    function test_points_unlock_50() public {
        vm.startPrank(admin);

        PointsModule.MintPoints memory mintParams = PointsModule.MintPoints({to: alice, amount: 100e18});
        pointsModProxy.mintTo(mintParams);

        vm.startPrank(alice);

        skip((365 days * 5) / 10); // 50% vest

        assertEq(pointsModProxy.getUnlockTax(alice), 0.5e18);

        pointsModProxy.unlockAll();

        assertEq(pointsModProxy.balanceOf(alice), 50e18);
        assertEq(pointsModProxy.balanceOf(treasury), 50e18);
        assertEq(pointsModProxy.lockedBalance(alice), 0);
        assertEq(pointsModProxy.unlockTime(alice), 0);
        assertEq(pointsModProxy.getUnlockTax(alice), 0);

        pointsModProxy.transfer(bob, 50e18);
    }

    function test_points_unlock_90() public {
        vm.startPrank(admin);

        PointsModule.MintPoints memory mintParams = PointsModule.MintPoints({to: alice, amount: 100e18});
        pointsModProxy.mintTo(mintParams);

        vm.startPrank(alice);

        skip((365 days * 9) / 10); // 90% vest

        assertEq(pointsModProxy.getUnlockTax(alice), 0.1e18);

        pointsModProxy.unlockAll();

        assertEq(pointsModProxy.balanceOf(alice), 90e18);
        assertEq(pointsModProxy.balanceOf(treasury), 10e18);
        assertEq(pointsModProxy.lockedBalance(alice), 0);
        assertEq(pointsModProxy.unlockTime(alice), 0);
        assertEq(pointsModProxy.getUnlockTax(alice), 0);
    }

    function test_points_unlock_100() public {
        vm.startPrank(admin);

        PointsModule.MintPoints memory mintParams = PointsModule.MintPoints({to: alice, amount: 100e18});
        pointsModProxy.mintTo(mintParams);

        vm.startPrank(alice);

        skip(365 days); // 100% vest

        assertEq(pointsModProxy.getUnlockTax(alice), 0);

        pointsModProxy.unlockAll();

        assertEq(pointsModProxy.balanceOf(alice), 100e18);
        assertEq(pointsModProxy.balanceOf(treasury), 0);
        assertEq(pointsModProxy.lockedBalance(alice), 0);
        assertEq(pointsModProxy.unlockTime(alice), 0);
        assertEq(pointsModProxy.getUnlockTax(alice), 0);
    }

    function test_points_unlock_200() public {
        vm.startPrank(admin);

        PointsModule.MintPoints memory mintParams = PointsModule.MintPoints({to: alice, amount: 100e18});
        pointsModProxy.mintTo(mintParams);

        vm.startPrank(alice);

        skip(365 days * 2); // 100% vest + additional time

        assertEq(pointsModProxy.getUnlockTax(alice), 0);

        pointsModProxy.unlockAll();

        assertEq(pointsModProxy.balanceOf(alice), 100e18);
        assertEq(pointsModProxy.balanceOf(treasury), 0);
        assertEq(pointsModProxy.lockedBalance(alice), 0);
        assertEq(pointsModProxy.unlockTime(alice), 0);
        assertEq(pointsModProxy.getUnlockTax(alice), 0);
    }

    function test_points_unlock_amount_no_vesting_period() public {
        vm.startPrank(admin);

        PointsModule.MintPoints memory mintParams = PointsModule.MintPoints({to: alice, amount: 100e18});
        pointsModProxy.mintTo(mintParams);
        uint256 unlockTime = block.timestamp + 365 days;

        vm.startPrank(alice);

        // 0% vest

        assertEq(pointsModProxy.getUnlockTax(alice), 1e18);

        pointsModProxy.unlock(50e18);

        assertEq(pointsModProxy.balanceOf(alice), 50e18);
        assertEq(pointsModProxy.balanceOf(treasury), 50e18);
        assertEq(pointsModProxy.lockedBalance(alice), 50e18);
        assertEq(pointsModProxy.unlockTime(alice), unlockTime);
        assertEq(pointsModProxy.getUnlockTax(alice), 1e18);

        vm.expectRevert("ERC20LockableUpgradeable: insufficient unlocked balance");
        pointsModProxy.transfer(bob, 1);

        skip((365 days * 5) / 10); // 50% vest

        pointsModProxy.unlock(type(uint256).max);

        assertEq(pointsModProxy.balanceOf(alice), 25e18);
        assertEq(pointsModProxy.balanceOf(treasury), 75e18);
        assertEq(pointsModProxy.lockedBalance(alice), 0);
        assertEq(pointsModProxy.unlockTime(alice), 0);
        assertEq(pointsModProxy.getUnlockTax(alice), 0);
    }

    function test_points_unlock_amount_50_percent_vesting() public {
        vm.startPrank(admin);

        PointsModule.MintPoints memory mintParams = PointsModule.MintPoints({to: alice, amount: 100e18});
        pointsModProxy.mintTo(mintParams);
        uint256 unlockTime = block.timestamp + 365 days;

        vm.startPrank(alice);

        skip((365 days * 5) / 10); // 50% vest

        assertEq(pointsModProxy.getUnlockTax(alice), 0.5e18);

        pointsModProxy.unlock(50e18);

        assertEq(pointsModProxy.balanceOf(alice), 75e18);
        assertEq(pointsModProxy.balanceOf(treasury), 25e18);
        assertEq(pointsModProxy.lockedBalance(alice), 50e18);
        assertEq(pointsModProxy.unlockTime(alice), block.timestamp + (365 days * 5) / 10);
        assertEq(pointsModProxy.getUnlockTax(alice), 0.5e18);

        vm.expectRevert("ERC20LockableUpgradeable: insufficient unlocked balance");
        pointsModProxy.transfer(bob, 25e18 + 1);

        pointsModProxy.transfer(bob, 25e18);

        skip(365 days); // 100% vest

        pointsModProxy.unlock(10e18);

        assertEq(pointsModProxy.balanceOf(alice), 50e18);
        assertEq(pointsModProxy.balanceOf(treasury), 25e18);
        assertEq(pointsModProxy.lockedBalance(alice), 40e18);
        assertEq(pointsModProxy.unlockTime(alice), unlockTime);
        assertEq(pointsModProxy.getUnlockTax(alice), 0);
    }

    function test_points_unlock_amount_100_percent_vesting() public {
        vm.startPrank(admin);

        PointsModule.MintPoints memory mintParams = PointsModule.MintPoints({to: alice, amount: 100e18});
        pointsModProxy.mintTo(mintParams);
        uint256 unlockTime = block.timestamp + 365 days;

        vm.startPrank(alice);

        skip(365 days * 2); // 100% vest

        assertEq(pointsModProxy.getUnlockTax(alice), 0);

        pointsModProxy.unlock(50e18);

        assertEq(pointsModProxy.balanceOf(alice), 100e18);
        assertEq(pointsModProxy.balanceOf(treasury), 0);
        assertEq(pointsModProxy.lockedBalance(alice), 50e18);
        assertEq(pointsModProxy.unlockTime(alice), unlockTime);
        assertEq(pointsModProxy.getUnlockTax(alice), 0);

        vm.expectRevert("ERC20LockableUpgradeable: insufficient unlocked balance");
        pointsModProxy.transfer(bob, 50e18 + 1);

        pointsModProxy.transfer(bob, 25e18);

        pointsModProxy.unlock(10e18);

        assertEq(pointsModProxy.balanceOf(alice), 75e18);
        assertEq(pointsModProxy.balanceOf(treasury), 0);
        assertEq(pointsModProxy.lockedBalance(alice), 40e18);
        assertEq(pointsModProxy.unlockTime(alice), unlockTime);
        assertEq(pointsModProxy.getUnlockTax(alice), 0);

        pointsModProxy.unlock(40e18);

        assertEq(pointsModProxy.balanceOf(alice), 75e18);
        assertEq(pointsModProxy.balanceOf(treasury), 0);
        assertEq(pointsModProxy.lockedBalance(alice), 0);
        assertEq(pointsModProxy.unlockTime(alice), 0);
        assertEq(pointsModProxy.getUnlockTax(alice), 0);
    }

    function test_points_unlock_amount_max() public {
        vm.startPrank(admin);

        PointsModule.MintPoints memory mintParams = PointsModule.MintPoints({to: alice, amount: 100e18});
        pointsModProxy.mintTo(mintParams);

        vm.startPrank(alice);

        skip(365 days / 2); // 50% vest

        pointsModProxy.unlock(type(uint256).max);

        assertEq(pointsModProxy.balanceOf(alice), 50e18);
        assertEq(pointsModProxy.balanceOf(treasury), 50e18);
        assertEq(pointsModProxy.lockedBalance(alice), 0);
        assertEq(pointsModProxy.unlockTime(alice), 0);
        assertEq(pointsModProxy.getUnlockTax(alice), 0);
    }

    /**
     * Reverts
     */

    function test_revert_points_unlock_bigger_than_balance() public {
        vm.startPrank(admin);

        PointsModule.MintPoints memory mintParams = PointsModule.MintPoints({to: alice, amount: 100e18});
        pointsModProxy.mintTo(mintParams);

        vm.startPrank(alice);

        vm.expectRevert("ERC20LockableUpgradeable: requested unlock exceeds locked balance");
        pointsModProxy.unlock(200e18);
    }
}
