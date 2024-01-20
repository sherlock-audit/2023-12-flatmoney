// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import "forge-std/console2.sol";

import {Setup} from "../../helpers/Setup.sol";
import {OrderHelpers} from "../../helpers/OrderHelpers.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../../../src/interfaces/IChainlinkAggregatorV3.sol";
import {FlatcoinErrors} from "../../../src/libraries/FlatcoinErrors.sol";

contract LPTokenLock is Setup, OrderHelpers {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function test_unlock_when_stable_withdraw_order_expired() public {
        setWethPrice(1000e8);

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        uint256 aliceLPBalanceBefore = stableModProxy.balanceOf(alice);
        uint256 withdrawAmount = aliceLPBalanceBefore;

        // Announce redemption of a portion of the LP tokens.
        announceStableWithdraw({traderAccount: alice, withdrawAmount: withdrawAmount, keeperFeeAmount: 0});

        // Skip some time so that the order expires.
        skip(vaultProxy.maxExecutabilityAge() + vaultProxy.minExecutabilityAge() + 1);

        vm.startPrank(alice);

        // Cancel the order.
        delayedOrderProxy.cancelExistingOrder(alice);

        assertEq(stableModProxy.getLockedAmount(alice), 0, "Locked amount should be 0");
        assertEq(stableModProxy.balanceOf(alice), aliceLPBalanceBefore, "Alice should have all the LP tokens");

        // When trying to transfer all the LP tokens, the transaction should not revert.
        IERC20Upgradeable(address(stableModProxy)).safeTransfer({to: bob, value: aliceLPBalanceBefore});

        assertEq(stableModProxy.balanceOf(bob), aliceLPBalanceBefore, "Bob should have gotten all the LP tokens");
    }

    function test_revert_lock_partial_stable_withdraw_announced() public {
        setWethPrice(1000e8);

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        uint256 aliceLPBalanceBefore = stableModProxy.balanceOf(alice);
        uint256 withdrawAmount = aliceLPBalanceBefore / 2;

        // Announce redemption of a portion of the LP tokens.
        announceStableWithdraw({traderAccount: alice, withdrawAmount: withdrawAmount, keeperFeeAmount: 0});

        vm.startPrank(alice);

        // When trying to transfer all the LP tokens, the transaction should revert.
        vm.expectRevert("ERC20LockableUpgradeable: insufficient unlocked balance");

        stableModProxy.transfer({to: bob, amount: aliceLPBalanceBefore});

        // Skip some time to make the order executable.
        skip(vaultProxy.minExecutabilityAge() + 1);

        executeStableWithdraw({traderAccount: alice, keeperAccount: keeper, oraclePrice: 1000e8});
    }

    function test_revert_lock_full_stable_withdraw_announced() public {
        setWethPrice(1000e8);

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        uint256 aliceLPBalanceBefore = stableModProxy.balanceOf(alice);
        uint256 withdrawAmount = aliceLPBalanceBefore;

        // Announce redemption of a portion of the LP tokens.
        announceStableWithdraw({traderAccount: alice, withdrawAmount: withdrawAmount, keeperFeeAmount: 0});

        vm.startPrank(alice);

        // When trying to transfer all the LP tokens, the transaction should revert.
        vm.expectRevert("ERC20LockableUpgradeable: insufficient unlocked balance");

        stableModProxy.transfer({to: bob, amount: aliceLPBalanceBefore});

        // Skip some time to make the order executable.
        skip(vaultProxy.minExecutabilityAge() + 1);

        executeStableWithdraw({traderAccount: alice, keeperAccount: keeper, oraclePrice: 1000e8});
    }

    function test_revert_lock_when_called_by_unauthorized_address() public {
        setWethPrice(1000e8);

        // Execute a deposit to mint new flatcoins.
        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        uint256 aliceLPBalance = stableModProxy.balanceOf(alice);

        vm.startPrank(carol);

        // Given that Carol is not an authorized address, the transaction should revert.
        vm.expectRevert(abi.encodeWithSelector(FlatcoinErrors.OnlyAuthorizedModule.selector, carol));

        stableModProxy.lock(alice, aliceLPBalance);
    }

    function test_revert_unlock_when_called_by_unauthorized_address() public {
        setWethPrice(1000e8);

        // Execute a deposit to mint new flatcoins.
        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        uint256 aliceLPBalance = stableModProxy.balanceOf(alice);

        // Announce redemption of a portion of the LP tokens.
        announceStableWithdraw({traderAccount: alice, withdrawAmount: aliceLPBalance, keeperFeeAmount: 0});

        vm.startPrank(carol);

        // Given that Carol is not an authorized address, the transaction should revert.
        vm.expectRevert(abi.encodeWithSelector(FlatcoinErrors.OnlyAuthorizedModule.selector, carol));

        stableModProxy.unlock(alice, aliceLPBalance);
    }
}
