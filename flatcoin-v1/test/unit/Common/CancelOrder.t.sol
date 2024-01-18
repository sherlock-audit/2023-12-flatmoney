// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {OrderHelpers} from "../../helpers/OrderHelpers.sol";
import {FlatcoinStructs} from "../../../src/libraries/FlatcoinStructs.sol";
import {IDelayedOrder} from "../../../src/interfaces/IDelayedOrder.sol";

import "forge-std/console2.sol";

contract CancelDepositTest is Setup, OrderHelpers {
    function test_cancel_deposit() public {
        cancelDeposit();
        cancelDeposit();
        cancelDeposit(); // third one for luck, just to make sure it all works
    }

    function test_cancel_withdraw() public {
        cancelWithdraw();
        cancelWithdraw();
        cancelWithdraw();
    }

    function test_cancel_leverage_open() public {
        cancelLeverageOpen();
        cancelLeverageOpen();
        cancelLeverageOpen();
    }

    function test_cancel_leverage_close() public {
        cancelLeverageClose();
        cancelLeverageClose();
        cancelLeverageClose();
    }

    // TODO: Consider moving helper functions to a separate contract

    function cancelDeposit() public {
        setWethPrice(2000e8);
        skip(120);

        // First deposit mint doesn't use offchain oracle price
        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });

        announceStableDeposit({traderAccount: alice, depositAmount: 100e18, keeperFeeAmount: 0});

        skip(vaultProxy.maxExecutabilityAge() + vaultProxy.minExecutabilityAge() + 1);
        vm.prank(alice);
        delayedOrderProxy.cancelExistingOrder(alice);

        FlatcoinStructs.Order memory order = delayedOrderProxy.getAnnouncedOrder(alice);

        assertEq(uint256(order.orderType), uint256(FlatcoinStructs.OrderType.None), "Order not cancelled");

        assertTrue(order.orderData.length == 0, "Order not cancelled");
    }

    function cancelWithdraw() public {
        setWethPrice(2000e8);
        skip(120);

        // First deposit mint doesn't use offchain oracle price
        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });

        announceStableWithdraw({traderAccount: alice, withdrawAmount: 100e18, keeperFeeAmount: 0});

        skip(vaultProxy.maxExecutabilityAge() + vaultProxy.minExecutabilityAge() + 1);
        vm.prank(alice);
        delayedOrderProxy.cancelExistingOrder(alice);

        FlatcoinStructs.Order memory order = delayedOrderProxy.getAnnouncedOrder(alice);

        assertEq(uint256(order.orderType), uint256(FlatcoinStructs.OrderType.None), "Order not cancelled");

        assertTrue(order.orderData.length == 0, "Order not cancelled");
    }

    function cancelLeverageOpen() public {
        setWethPrice(2000e8);
        skip(120);

        // First deposit mint doesn't use offchain oracle price
        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });

        announceOpenLeverage({traderAccount: alice, margin: 100e18, additionalSize: 100e18, keeperFeeAmount: 0});

        skip(vaultProxy.maxExecutabilityAge() + vaultProxy.minExecutabilityAge() + 1);
        vm.prank(alice);
        delayedOrderProxy.cancelExistingOrder(alice);

        FlatcoinStructs.Order memory order = delayedOrderProxy.getAnnouncedOrder(alice);

        assertEq(uint256(order.orderType), uint256(FlatcoinStructs.OrderType.None), "Order not cancelled");

        assertTrue(order.orderData.length == 0, "Order not cancelled");
    }

    function cancelLeverageClose() public {
        setWethPrice(2000e8);
        skip(120);

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });

        uint256 tokenId0 = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 100e18,
            additionalSize: 100e18,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });

        announceCloseLeverage({traderAccount: alice, tokenId: tokenId0, keeperFeeAmount: 0});

        skip(vaultProxy.maxExecutabilityAge() + vaultProxy.minExecutabilityAge() + 1);

        vm.startPrank(alice);
        delayedOrderProxy.cancelExistingOrder(alice);

        FlatcoinStructs.Order memory order = delayedOrderProxy.getAnnouncedOrder(alice);

        assertEq(uint256(order.orderType), uint256(FlatcoinStructs.OrderType.None), "Order not cancelled");

        assertTrue(order.orderData.length == 0, "Order not cancelled");
    }
}
