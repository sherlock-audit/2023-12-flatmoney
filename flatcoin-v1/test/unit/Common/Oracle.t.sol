// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {IPyth} from "pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "pyth-sdk-solidity/PythStructs.sol";

import {FlatcoinErrors} from "../../../src/libraries/FlatcoinErrors.sol";
import {Setup} from "../../helpers/Setup.sol";
import "../../helpers/OrderHelpers.sol";

import "forge-std/console2.sol";

contract OracleTest is Setup, OrderHelpers {
    function test_oracle_get_price_full_update() public {
        uint256 wethPrice = 2200e8;
        // update onchain and offchain price
        setWethPrice(wethPrice);
        skip(10);

        (uint256 price, uint256 timestamp) = oracleModProxy.getPrice();
        assertEq(price, wethPrice * 1e10, "Invalid oracle price");
        assertEq(timestamp, block.timestamp - 10, "Invalid timestamp");
    }

    function test_oracle_get_price_onchain_update() public {
        uint256 wethPriceOld = 1000e8;
        uint256 wethPriceNew = 2500e8;

        setWethPrice(wethPriceOld);

        skip(1);

        // Update WETH price on Chainlink only
        vm.mockCall(
            address(wethChainlinkAggregatorV3),
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(0, wethPriceNew, 0, block.timestamp, 0)
        );

        (uint256 price, uint256 timestamp) = oracleModProxy.getPrice(); // should return the Chainlink price because it's fresher
        assertEq(price, wethPriceNew * 1e10, "Invalid oracle price");
        assertEq(timestamp, block.timestamp, "Invalid timestamp");
    }

    function test_oracle_get_price_offchain_update() public {
        uint256 wethPriceOld = 1000e8;
        uint256 wethPriceNew = 1500e8;

        setWethPrice(wethPriceOld);

        skip(1);

        // Update Pyth network price
        bytes[] memory priceUpdateData = getPriceUpdateData(wethPriceNew);
        oracleModProxy.updatePythPrice{value: 1}(msg.sender, priceUpdateData);

        (uint256 price, uint256 timestamp) = oracleModProxy.getPrice();
        assertEq(price, wethPriceNew * 1e10, "Invalid oracle price");
        assertEq(timestamp, block.timestamp, "Invalid timestamp");
    }

    // Should return the Offchain price if both onchain and offchain prices have the same timestamp
    function test_oracle_get_price_difference() public {
        uint256 wethPriceOnchain = 2499e8;
        uint256 wethPriceOffchain = 2500e8;

        skip(1);

        // Update Chainlink price
        vm.mockCall(
            address(wethChainlinkAggregatorV3),
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(0, wethPriceOnchain, 0, block.timestamp, 0)
        );

        // Update Pyth network price
        bytes[] memory priceUpdateData = getPriceUpdateData(wethPriceOffchain);
        oracleModProxy.updatePythPrice{value: 1}(msg.sender, priceUpdateData);

        (uint256 price, uint256 timestamp) = oracleModProxy.getPrice();
        assertEq(price, wethPriceOffchain * 1e10, "Invalid oracle price"); // should return the offchain price, not onchain
        assertEq(timestamp, block.timestamp, "Invalid timestamp");
    }

    function test_oracle_get_price_max_age() public {
        uint256 wethPrice = 2500e8;

        setWethPrice(wethPrice);

        skip(1);

        (uint256 price, uint256 timestamp) = oracleModProxy.getPrice({maxAge: 5});
        assertEq(price, wethPrice * 1e10, "Invalid oracle price");
        assertEq(timestamp, block.timestamp - 1, "Invalid timestamp");

        skip(5);

        vm.expectRevert(
            abi.encodeWithSelector(FlatcoinErrors.PriceStale.selector, FlatcoinErrors.PriceSource.OffChain)
        );
        (price, timestamp) = oracleModProxy.getPrice({maxAge: 5});

        // Update Pyth network price
        bytes[] memory priceUpdateData = getPriceUpdateData(wethPrice);
        oracleModProxy.updatePythPrice{value: 1}(msg.sender, priceUpdateData);

        (price, timestamp) = oracleModProxy.getPrice({maxAge: 5});
        assertEq(price, wethPrice * 1e10, "Invalid oracle price");
        assertEq(timestamp, block.timestamp, "Invalid timestamp");

        // Update Chainlink price
        vm.mockCall(
            address(wethChainlinkAggregatorV3),
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(0, wethPrice, 0, block.timestamp, 0)
        );

        (price, timestamp) = oracleModProxy.getPrice({maxAge: 5});
        assertEq(price, wethPrice * 1e10, "Invalid oracle price");
        assertEq(timestamp, block.timestamp, "Invalid timestamp");
    }

    function test_oracle_price_mismatch() public {
        vm.startPrank(admin);
        oracleModProxy.setMaxDiffPercent(0.01e18); // 1% maximum difference between onchain and offchain price

        // Lower and within 1% - should pass
        {
            uint256 wethPriceOnchain = 1000e8;
            uint256 wethPriceOffchain = 991e8;

            skip(1);

            // Update Chainlink price
            vm.mockCall(
                address(wethChainlinkAggregatorV3),
                abi.encodeWithSignature("latestRoundData()"),
                abi.encode(0, wethPriceOnchain, 0, block.timestamp, 0)
            );

            // Update Pyth network price
            bytes[] memory priceUpdateData = getPriceUpdateData(wethPriceOffchain);
            oracleModProxy.updatePythPrice{value: 1}(msg.sender, priceUpdateData);

            oracleModProxy.getPrice();
        }

        // Lower and outside 1% - should revert
        {
            uint256 wethPriceOnchain = 1000e8;
            uint256 wethPriceOffchain = 989e8;
            uint256 priceDiffPercent = 0.011e18; // 1.1%

            skip(1);

            // Update Chainlink price
            vm.mockCall(
                address(wethChainlinkAggregatorV3),
                abi.encodeWithSignature("latestRoundData()"),
                abi.encode(0, wethPriceOnchain, 0, block.timestamp, 0)
            );

            // Update Pyth network price
            bytes[] memory priceUpdateData = getPriceUpdateData(wethPriceOffchain);
            oracleModProxy.updatePythPrice{value: 1}(msg.sender, priceUpdateData);

            vm.expectRevert(abi.encodeWithSelector(FlatcoinErrors.PriceMismatch.selector, priceDiffPercent));
            oracleModProxy.getPrice();
        }

        // Higher and within 1% - should pass
        {
            uint256 wethPriceOnchain = 1000e8;
            uint256 wethPriceOffchain = 1009e8;

            skip(1);

            // Update Chainlink price
            vm.mockCall(
                address(wethChainlinkAggregatorV3),
                abi.encodeWithSignature("latestRoundData()"),
                abi.encode(0, wethPriceOnchain, 0, block.timestamp, 0)
            );

            // Update Pyth network price
            bytes[] memory priceUpdateData = getPriceUpdateData(wethPriceOffchain);
            oracleModProxy.updatePythPrice{value: 1}(msg.sender, priceUpdateData);

            oracleModProxy.getPrice();
        }

        // Higher and outside 1% - should revert
        {
            uint256 wethPriceOnchain = 1000e8;
            uint256 wethPriceOffchain = 1011e8;
            uint256 priceDiffPercent = 0.011e18; // 1.1%

            skip(1);

            // Update Chainlink price
            vm.mockCall(
                address(wethChainlinkAggregatorV3),
                abi.encodeWithSignature("latestRoundData()"),
                abi.encode(0, wethPriceOnchain, 0, block.timestamp, 0)
            );

            // Update Pyth network price
            bytes[] memory priceUpdateData = getPriceUpdateData(wethPriceOffchain);
            oracleModProxy.updatePythPrice{value: 1}(msg.sender, priceUpdateData);

            vm.expectRevert(abi.encodeWithSelector(FlatcoinErrors.PriceMismatch.selector, priceDiffPercent));
            oracleModProxy.getPrice();
        }
    }
}
