// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {LimitOrder} from "src/LimitOrder.sol";
import {FlatcoinStructs} from "src/libraries/FlatcoinStructs.sol";
import {FlatcoinErrors} from "src/libraries/FlatcoinErrors.sol";
import {ExpectRevert} from "../../helpers/ExpectRevert.sol";
import {OrderHelpers} from "../../helpers/OrderHelpers.sol";

import "forge-std/console2.sol";

contract LimitOrderTest is OrderHelpers, ExpectRevert {
    uint256 tokenId;
    uint256 keeperFee;

    function setUp() public override {
        super.setUp();

        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;
        keeperFee = mockKeeperFee.getKeeperFee();

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 10e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        // second leverage position where tokenId > 0, to ensure proper checks later
        tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 10e18,
            additionalSize: 30e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });
    }

    function test_revert_announce_limit_order() public {
        vm.startPrank(alice);

        _expectRevertWithCustomError({
            target: address(limitOrderProxy),
            callData: abi.encodeWithSelector(LimitOrder.announceLimitOrder.selector, tokenId, 1100e18, 900e18),
            expectedErrorSignature: "InvalidThresholds(uint256,uint256)",
            errorData: abi.encodeWithSelector(FlatcoinErrors.InvalidThresholds.selector, 1100e18, 900e18)
        });

        vm.startPrank(bob);

        _expectRevertWithCustomError({
            target: address(limitOrderProxy),
            callData: abi.encodeWithSelector(LimitOrder.announceLimitOrder.selector, tokenId, 900e18, 1100e18),
            expectedErrorSignature: "NotTokenOwner(uint256,address)",
            errorData: abi.encodeWithSelector(FlatcoinErrors.NotTokenOwner.selector, tokenId, address(bob))
        });
    }

    function test_revert_execute_limit_order() public {
        uint256 collateralPrice = 1000e8;

        vm.startPrank(alice);

        limitOrderProxy.announceLimitOrder({
            tokenId: tokenId,
            priceLowerThreshold: 900e18,
            priceUpperThreshold: 1100e18
        });

        FlatcoinStructs.Order memory order = limitOrderProxy.getLimitOrder(tokenId);

        bytes[] memory priceUpdateData = getPriceUpdateData(collateralPrice);

        _expectRevertWithCustomError({
            target: address(limitOrderProxy),
            callData: abi.encodeWithSelector(LimitOrder.executeLimitOrder.selector, tokenId, priceUpdateData),
            expectedErrorSignature: "ExecutableTimeNotReached(uint256)",
            errorData: abi.encodeWithSelector(FlatcoinErrors.ExecutableTimeNotReached.selector, order.executableAtTime),
            value: 1
        });

        skip(1); // skip 1 second so that the new price update is valid
        bytes[] memory priceUpdateDataStale = getPriceUpdateData(899e8);

        skip(uint256(vaultProxy.minExecutabilityAge()));

        _expectRevertWithCustomError({
            target: address(limitOrderProxy),
            callData: abi.encodeWithSelector(LimitOrder.executeLimitOrder.selector, tokenId, priceUpdateDataStale),
            expectedErrorSignature: "PriceStale(uint8)",
            errorData: abi.encodeWithSelector(FlatcoinErrors.PriceStale.selector, FlatcoinErrors.PriceSource.OffChain),
            value: 1
        });

        // reverts when price > order priceLowerThreshold
        priceUpdateData = getPriceUpdateData(901e8);
        _expectRevertWithCustomError({
            target: address(limitOrderProxy),
            callData: abi.encodeWithSelector(LimitOrder.executeLimitOrder.selector, tokenId, priceUpdateData),
            expectedErrorSignature: "LimitOrderPriceNotInRange(uint256,uint256,uint256)",
            errorData: abi.encodeWithSelector(
                FlatcoinErrors.LimitOrderPriceNotInRange.selector,
                901e18,
                900e18,
                1100e18
            ),
            value: 1
        });

        // reverts when price < order priceUpperThreshold
        priceUpdateData = getPriceUpdateData(1099e8);
        _expectRevertWithCustomError({
            target: address(limitOrderProxy),
            callData: abi.encodeWithSelector(LimitOrder.executeLimitOrder.selector, tokenId, priceUpdateData),
            expectedErrorSignature: "LimitOrderPriceNotInRange(uint256,uint256,uint256)",
            errorData: abi.encodeWithSelector(
                FlatcoinErrors.LimitOrderPriceNotInRange.selector,
                1099e18,
                900e18,
                1100e18
            ),
            value: 1
        });
    }

    function test_limit_order_price_below_lower_threshold() public {
        uint256 collateralPrice = 899e8;

        announceAndExecuteLimitClose({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            priceLowerThreshold: 900e18,
            priceUpperThreshold: 1100e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: keeperFee
        });
    }

    function test_limit_order_price_equal_lower_threshold() public {
        uint256 collateralPrice = 900e8;

        announceAndExecuteLimitClose({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            priceLowerThreshold: 900e18,
            priceUpperThreshold: 1100e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: keeperFee
        });
    }

    function test_limit_order_price_equal_upper_threshold() public {
        uint256 collateralPrice = 1100e8;

        announceAndExecuteLimitClose({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            priceLowerThreshold: 900e18,
            priceUpperThreshold: 1100e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: keeperFee
        });
    }

    function test_limit_order_price_above_upper_threshold() public {
        uint256 collateralPrice = 1101e8;

        announceAndExecuteLimitClose({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            priceLowerThreshold: 900e18,
            priceUpperThreshold: 1100e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: keeperFee
        });
    }

    function test_limit_order_removal_after_position_close() public {
        uint256 collateralPrice = 1000e8;

        vm.startPrank(alice);

        limitOrderProxy.announceLimitOrder({
            tokenId: tokenId,
            priceLowerThreshold: 900e18,
            priceUpperThreshold: 1100e18
        });

        announceAndExecuteLeverageClose({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        FlatcoinStructs.Order memory order = limitOrderProxy.getLimitOrder(tokenId);

        assertEq(uint256(order.orderType), 0);
        assertEq(order.keeperFee, 0);
        assertEq(order.executableAtTime, 0);
    }

    function test_limit_order_removal_after_position_liquidation() public {
        vm.startPrank(alice);

        limitOrderProxy.announceLimitOrder({
            tokenId: tokenId,
            priceLowerThreshold: 900e18,
            priceUpperThreshold: 1100e18
        });

        setWethPrice(750e8);

        liquidationModProxy.liquidate(tokenId);

        FlatcoinStructs.Order memory order = limitOrderProxy.getLimitOrder(tokenId);

        assertEq(uint256(order.orderType), 0);
        assertEq(order.keeperFee, 0);
        assertEq(order.executableAtTime, 0);
    }
}
