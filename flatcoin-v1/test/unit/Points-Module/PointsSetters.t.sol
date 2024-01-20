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

contract PointsSettersTest is Setup, OrderHelpers, ExpectRevert {
    function test_points_setters() public {
        vm.startPrank(admin);

        pointsModProxy.setPointsVest(86400, 1000e18, 2000e18);
        pointsModProxy.setTreasury(bob);

        assertEq(pointsModProxy.unlockTaxVest(), 86400);
        assertEq(pointsModProxy.pointsPerSize(), 1000e18);
        assertEq(pointsModProxy.pointsPerDeposit(), 2000e18);
        assertEq(pointsModProxy.treasury(), bob);
    }

    /**
     * Reverts
     */

    function test_revert_points_setters_when_caller_not_owner() public {
        vm.startPrank(alice);

        _expectRevertWithCustomError({
            target: address(pointsModProxy),
            callData: abi.encodeWithSelector(PointsModule.setPointsVest.selector, 10000, 1000e18, 2000e18),
            expectedErrorSignature: "OnlyOwner(address)",
            errorData: abi.encodeWithSelector(FlatcoinErrors.OnlyOwner.selector, alice)
        });

        _expectRevertWithCustomError({
            target: address(pointsModProxy),
            callData: abi.encodeWithSelector(PointsModule.setTreasury.selector, bob),
            expectedErrorSignature: "OnlyOwner(address)",
            errorData: abi.encodeWithSelector(FlatcoinErrors.OnlyOwner.selector, alice)
        });
    }
}
