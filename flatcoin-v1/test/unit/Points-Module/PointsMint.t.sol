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

contract PointsMintTest is Setup, OrderHelpers, ExpectRevert {
    function test_points_mint_to() public {
        vm.startPrank(admin);

        PointsModule.MintPoints memory mintParams = PointsModule.MintPoints({to: alice, amount: 100e18});
        pointsModProxy.mintTo(mintParams);

        vm.startPrank(alice);

        vm.expectRevert("ERC20LockableUpgradeable: insufficient unlocked balance");
        pointsModProxy.transfer(bob, 1e18);

        assertEq(pointsModProxy.balanceOf(alice), 100e18);
        assertEq(pointsModProxy.totalSupply(), 100e18);
        assertEq(pointsModProxy.lockedBalance(alice), 100e18);
        assertEq(pointsModProxy.unlockTime(alice), block.timestamp + 365 days);
        assertEq(pointsModProxy.getUnlockTax(alice), 1e18);
    }

    function test_points_mint_to_multiple() public {
        vm.startPrank(admin);

        address[] memory mintAccounts = new address[](2);
        uint256[] memory mintAmounts = new uint256[](2);
        mintAccounts[0] = alice;
        mintAccounts[1] = bob;
        mintAmounts[0] = 100e18;
        mintAmounts[1] = 200e18;

        PointsModule.MintPoints[] memory mintParams = new PointsModule.MintPoints[](mintAccounts.length);

        for (uint256 i = 0; i < mintAccounts.length; i++) {
            mintParams[i] = PointsModule.MintPoints({to: mintAccounts[i], amount: mintAmounts[i]});
        }
        pointsModProxy.mintToMultiple(mintParams);

        assertEq(pointsModProxy.balanceOf(alice), 100e18);
        assertEq(pointsModProxy.balanceOf(bob), 200e18);
        assertEq(pointsModProxy.totalSupply(), 300e18);
        assertEq(pointsModProxy.unlockTime(alice), block.timestamp + 365 days);
        assertEq(pointsModProxy.getUnlockTax(alice), 1e18);
        assertEq(pointsModProxy.unlockTime(bob), block.timestamp + 365 days);
        assertEq(pointsModProxy.getUnlockTax(bob), 1e18);
    }

    function test_points_mint_after_expiry() public {
        vm.startPrank(admin);

        PointsModule.MintPoints memory mintParams = PointsModule.MintPoints({to: alice, amount: 100e18});
        pointsModProxy.mintTo(mintParams);

        skip(365 days * 2); // 100% vest + additional time

        assertEq(pointsModProxy.unlockTime(alice), block.timestamp - 365 days);
        assertEq(pointsModProxy.getUnlockTax(alice), 0);

        mintParams = PointsModule.MintPoints({to: alice, amount: 200e18});
        pointsModProxy.mintTo(mintParams);

        assertEq(pointsModProxy.balanceOf(alice), 300e18);
        assertEq(pointsModProxy.lockedBalance(alice), 200e18);
        assertEq(pointsModProxy.unlockTime(alice), block.timestamp + 365 days);
        assertEq(pointsModProxy.getUnlockTax(alice), 1e18);

        vm.startPrank(alice);

        vm.expectRevert("ERC20LockableUpgradeable: insufficient unlocked balance");
        pointsModProxy.transfer(bob, 300e18);

        pointsModProxy.transfer(bob, 100e18);

        assertEq(pointsModProxy.balanceOf(alice), 200e18);
        assertEq(pointsModProxy.lockedBalance(alice), 200e18);
    }

    function test_points_mint_before_expiry_50() public {
        vm.startPrank(admin);

        uint256 firstMintAmount = 100e18;
        uint256 secondMintAmount = 100e18;

        PointsModule.MintPoints memory mintParams = PointsModule.MintPoints({to: alice, amount: firstMintAmount});
        pointsModProxy.mintTo(mintParams);

        skip(365 days / 2); // 50% vest

        mintParams = PointsModule.MintPoints({to: alice, amount: secondMintAmount});
        pointsModProxy.mintTo(mintParams);

        assertEq(pointsModProxy.balanceOf(alice), 200e18);
        assertEq(pointsModProxy.lockedBalance(alice), 200e18);
        assertEq(pointsModProxy.unlockTime(alice), block.timestamp + ((365 days * 3) / 4));
        assertEq(pointsModProxy.getUnlockTax(alice), 0.75e18);

        vm.expectRevert("ERC20LockableUpgradeable: insufficient unlocked balance");
        pointsModProxy.transfer(bob, 1);

        vm.startPrank(alice);

        pointsModProxy.unlockAll();

        assertEq(pointsModProxy.lockedBalance(alice), 0);
        assertEq(pointsModProxy.balanceOf(alice), 50e18);
        assertEq(pointsModProxy.balanceOf(treasury), 150e18);

        vm.expectRevert("ERC20LockableUpgradeable: insufficient unlocked balance");
        pointsModProxy.transfer(bob, 50e18 + 1);

        pointsModProxy.transfer(bob, 50e18);

        assertEq(pointsModProxy.balanceOf(alice), 0);
        assertEq(pointsModProxy.lockedBalance(alice), 0);
        assertEq(pointsModProxy.balanceOf(bob), 50e18);
        assertEq(pointsModProxy.lockedBalance(bob), 0);
    }

    function test_points_mint_before_expiry_0() public {
        vm.startPrank(admin);

        uint256 firstMintAmount = 123e18;
        uint256 secondMintAmount = 456e18;

        PointsModule.MintPoints memory mintParams = PointsModule.MintPoints({to: alice, amount: firstMintAmount});
        pointsModProxy.mintTo(mintParams);

        mintParams = PointsModule.MintPoints({to: alice, amount: secondMintAmount});
        pointsModProxy.mintTo(mintParams);

        uint256 balance = pointsModProxy.balanceOf(alice);

        assertEq(pointsModProxy.unlockTime(alice), block.timestamp + 365 days);
        assertEq(pointsModProxy.lockedBalance(alice), balance);
        assertEq(pointsModProxy.getUnlockTax(alice), 1e18);

        vm.startPrank(alice);

        pointsModProxy.unlockAll();

        assertEq(pointsModProxy.lockedBalance(alice), 0);
    }

    function test_points_mint_before_expiry_90() public {
        vm.startPrank(admin);

        uint256 firstMintAmount = 100e18;
        uint256 secondMintAmount = 200e18;
        uint256 percentVest = 90;

        PointsModule.MintPoints memory mintParams = PointsModule.MintPoints({to: alice, amount: firstMintAmount});
        pointsModProxy.mintTo(mintParams);

        skip((365 days * percentVest) / 100);

        mintParams = PointsModule.MintPoints({to: alice, amount: secondMintAmount});
        pointsModProxy.mintTo(mintParams);

        uint256 balance = pointsModProxy.balanceOf(alice);

        assertEq(pointsModProxy.lockedBalance(alice), balance);

        vm.startPrank(alice);

        pointsModProxy.unlockAll();

        assertEq(pointsModProxy.lockedBalance(alice), 0);
        assertApproxEqAbs(pointsModProxy.balanceOf(alice), ((firstMintAmount * percentVest) / 100), 1e6);
        assertApproxEqAbs(
            pointsModProxy.balanceOf(treasury),
            secondMintAmount + ((firstMintAmount * (100 - percentVest)) / 100),
            1e6
        );
    }

    function test_points_mint_before_expiry_10() public {
        vm.startPrank(admin);

        uint256 firstMintAmount = 20e18;
        uint256 secondMintAmount = 10e18;
        uint256 percentVest = 10;

        PointsModule.MintPoints memory mintParams = PointsModule.MintPoints({to: alice, amount: firstMintAmount});
        pointsModProxy.mintTo(mintParams);

        skip((365 days * percentVest) / 100);

        mintParams = PointsModule.MintPoints({to: alice, amount: secondMintAmount});
        pointsModProxy.mintTo(mintParams);

        uint256 balance = pointsModProxy.balanceOf(alice);

        assertEq(pointsModProxy.lockedBalance(alice), balance);

        vm.startPrank(alice);

        pointsModProxy.unlockAll();

        assertEq(pointsModProxy.lockedBalance(alice), 0);
        assertApproxEqAbs(pointsModProxy.balanceOf(alice), ((firstMintAmount * percentVest) / 100), 1e6);
        assertApproxEqAbs(
            pointsModProxy.balanceOf(treasury),
            secondMintAmount + ((firstMintAmount * (100 - percentVest)) / 100),
            1e6
        );
    }

    /**
     * Reverts
     */

    function test_revert_points_mint_to() public {
        vm.startPrank(alice);

        PointsModule.MintPoints memory mintParams = PointsModule.MintPoints({to: alice, amount: 100e18});

        _expectRevertWithCustomError({
            target: address(pointsModProxy),
            callData: abi.encodeWithSelector(PointsModule.mintTo.selector, mintParams),
            expectedErrorSignature: "OnlyOwner(address)",
            errorData: abi.encodeWithSelector(FlatcoinErrors.OnlyOwner.selector, alice)
        });
    }

    function test_revert_points_mint_too_small() public {
        vm.startPrank(admin);

        PointsModule.MintPoints memory mintParams = PointsModule.MintPoints({to: alice, amount: 1e5});

        _expectRevertWithCustomError({
            target: address(pointsModProxy),
            callData: abi.encodeWithSelector(PointsModule.mintTo.selector, mintParams),
            expectedErrorSignature: "MintAmountTooLow(uint256)",
            errorData: abi.encodeWithSelector(FlatcoinErrors.MintAmountTooLow.selector, 1e5)
        });
    }
}
