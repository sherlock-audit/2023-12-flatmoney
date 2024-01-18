// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import "forge-std/console2.sol";

import {Setup} from "../../helpers/Setup.sol";
import {OrderHelpers} from "../../helpers/OrderHelpers.sol";
import "../../../src/interfaces/IChainlinkAggregatorV3.sol";

contract PositionLockTest is Setup, OrderHelpers {
    function test_lock_when_leverage_close_order_announced() public {
        setWethPrice(1000e8);

        uint256 tokenId = announceAndExecuteDepositAndLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            margin: 50e18,
            additionalSize: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        (uint256 minFillPrice, ) = oracleModProxy.getPrice();

        vm.startPrank(alice);

        // Announce the order
        delayedOrderProxy.announceLeverageClose({
            tokenId: tokenId,
            minFillPrice: minFillPrice,
            keeperFee: mockKeeperFee.getKeeperFee()
        });

        assertTrue(leverageModProxy.isLocked(tokenId), "Position NFT should be locked");

        vm.expectRevert("ERC721LockableEnumerableUpgradeable: token is locked");

        // Try to transfer the position.
        leverageModProxy.transferFrom({from: alice, to: bob, tokenId: tokenId});

        // Skip some time to make the order executable.
        skip(vaultProxy.minExecutabilityAge() + 1);

        // Execute the order
        executeCloseLeverage({keeperAccount: keeper, traderAccount: alice, oraclePrice: 1000e8});
    }

    function test_unlock_when_leverage_close_order_cancelled() public {
        setWethPrice(1000e8);

        uint256 tokenId = announceAndExecuteDepositAndLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            margin: 50e18,
            additionalSize: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        (uint256 minFillPrice, ) = oracleModProxy.getPrice();

        vm.startPrank(alice);

        // Announce the order
        delayedOrderProxy.announceLeverageClose({
            tokenId: tokenId,
            minFillPrice: minFillPrice,
            keeperFee: mockKeeperFee.getKeeperFee()
        });

        assertTrue(leverageModProxy.isLocked(tokenId), "Position NFT should be locked");

        vm.expectRevert("ERC721LockableEnumerableUpgradeable: token is locked");

        // Try to transfer the position.
        leverageModProxy.transferFrom({from: alice, to: bob, tokenId: tokenId});

        // Skip some time so that the order expires.
        skip(vaultProxy.maxExecutabilityAge() + vaultProxy.minExecutabilityAge() + 1);

        // Cancel the order.
        delayedOrderProxy.cancelExistingOrder(alice);

        assertFalse(leverageModProxy.isLocked(tokenId), "Position NFT should be unlocked");
        assertEq(leverageModProxy.ownerOf(tokenId), alice, "Alice should be the owner of the position NFT");

        vm.startPrank(alice);

        // Try to transfer the position.
        leverageModProxy.safeTransferFrom({from: alice, to: bob, tokenId: tokenId});

        assertEq(leverageModProxy.ownerOf(tokenId), bob, "Bob should be the owner of the position NFT");
    }
}
