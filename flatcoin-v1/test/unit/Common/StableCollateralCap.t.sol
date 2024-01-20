// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {FlatcoinVault} from "../../../src/FlatcoinVault.sol";
import {Setup} from "../../helpers/Setup.sol";
import {ExpectRevert} from "../../helpers/ExpectRevert.sol";
import {OrderHelpers} from "../../helpers/OrderHelpers.sol";
import {FlatcoinErrors} from "src/libraries/FlatcoinErrors.sol";

import "forge-std/console2.sol";

contract StableCollateralCapTest is Setup, OrderHelpers, ExpectRevert {
    function test_stable_collateral_cap_set() public {
        vm.startPrank(alice);

        _expectRevertWith({
            target: address(vaultProxy),
            callData: abi.encodeWithSelector(FlatcoinVault.setStableCollateralCap.selector, 1e18),
            revertMessage: "Ownable: caller is not the owner"
        });

        vm.startPrank(admin);

        vaultProxy.setStableCollateralCap(1e18);

        assertEq(vaultProxy.stableCollateralCap(), 1e18, "Max cap not set correctly");
    }

    function test_stable_collateral_cap_announce() public {
        uint256 collateralPrice = 1000e8;
        uint256 maxCap = 100e18;

        uint256 keeperFee = mockKeeperFee.getKeeperFee();

        vm.startPrank(admin);

        vaultProxy.setStableCollateralCap(maxCap);

        vm.startPrank(alice);

        // Depositing over the max cap should revert
        _expectRevertWithCustomError({
            target: address(this),
            callData: abi.encodeWithSelector(OrderHelpers.announceStableDeposit.selector, alice, maxCap + 1, keeperFee),
            expectedErrorSignature: "DepositCapReached(uint256)",
            ignoreErrorArguments: true
        });

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: maxCap,
            oraclePrice: collateralPrice,
            keeperFeeAmount: keeperFee
        });

        // Max cap already reached. Any further deposits should revert
        _expectRevertWithCustomError({
            target: address(this),
            callData: abi.encodeWithSelector(OrderHelpers.announceStableDeposit.selector, alice, 1, keeperFee),
            expectedErrorSignature: "DepositCapReached(uint256)",
            ignoreErrorArguments: true
        });
    }

    function test_stable_collateral_cap_execute() public {
        uint256 collateralPrice = 1000e8;
        uint256 maxCap = 100e18;

        uint256 keeperFee = mockKeeperFee.getKeeperFee();

        vm.startPrank(admin);

        vaultProxy.setStableCollateralCap(maxCap);

        vm.startPrank(alice);

        // Depositing over the max cap should revert
        _expectRevertWithCustomError({
            target: address(this),
            callData: abi.encodeWithSelector(OrderHelpers.announceStableDeposit.selector, alice, maxCap + 1, keeperFee),
            expectedErrorSignature: "DepositCapReached(uint256)",
            ignoreErrorArguments: true
        });

        // Alice and Bob both announce deposits
        announceStableDeposit({traderAccount: alice, depositAmount: maxCap, keeperFeeAmount: keeperFee});
        announceStableDeposit({traderAccount: bob, depositAmount: 1e18, keeperFeeAmount: keeperFee});

        skip(uint256(vaultProxy.minExecutabilityAge()));

        // bytes[] memory priceUpdateData = getPriceUpdateData(collateralPrice);

        // Alice's order executes first
        executeStableDeposit(keeper, alice, collateralPrice);

        // Now Bob's order reaches the cap
        _expectRevertWithCustomError({
            target: address(this),
            callData: abi.encodeWithSelector(
                OrderHelpers.executeStableDeposit.selector,
                keeper,
                bob,
                collateralPrice,
                false
            ),
            expectedErrorSignature: "DepositCapReached(uint256)",
            ignoreErrorArguments: true
        });

        // Withdraw some of Alice's tokens
        announceAndExecuteWithdraw({
            traderAccount: alice,
            keeperAccount: keeper,
            withdrawAmount: maxCap / 2,
            oraclePrice: collateralPrice,
            keeperFeeAmount: keeperFee
        });

        // Now Bob's order can execute
        executeStableDeposit(keeper, bob, collateralPrice);
    }
}
