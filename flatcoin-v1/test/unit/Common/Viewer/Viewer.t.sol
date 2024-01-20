// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {IPyth} from "pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "pyth-sdk-solidity/PythStructs.sol";

import {Setup} from "../../../helpers/Setup.sol";
import "../../../helpers/OrderHelpers.sol";

import "forge-std/console2.sol";

contract ViewerTest is Setup, OrderHelpers {
    function test_viewer_leverage_positions_account() public {
        vm.prank(admin);
        vaultProxy.setMaxFundingVelocity(0.03e18); // we want to see the funding rates in action for the viewer

        setWethPrice(2200e8);

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 2200e8,
            keeperFeeAmount: 0
        });

        setWethPrice(2500e8);

        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 70e18,
            additionalSize: 70e18,
            oraclePrice: 2500e8,
            keeperFeeAmount: 0
        });

        setWethPrice(2100e8);

        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 20e18,
            additionalSize: 20e18,
            oraclePrice: 2100e8,
            keeperFeeAmount: 0
        });

        setWethPrice(4000e8);

        skip(1 days); // skewed short slightly, so funding rate should decrease over time

        FlatcoinStructs.LeveragePositionData[] memory leveragePositions = viewer.getAccountLeveragePositionData(alice);
        for (uint256 i = 0; i < leveragePositions.length; i++) {
            assertEq(leveragePositions[i].tokenId, i, "invalid tokenId");
            assertGt(leveragePositions[i].lastPrice, 0, "invalid lastPrice");
            assertGt(leveragePositions[i].marginDeposited, 0, "invalid marginDeposited");
            assertGt(leveragePositions[i].additionalSize, 0, "invalid additionalSize");
            assertLt(leveragePositions[i].entryCumulativeFunding, 0, "invalid entryCumulativeFunding");
            assertGt(leveragePositions[i].profitLoss, 0, "invalid profitLoss");
            assertGt(leveragePositions[i].accruedFunding, 0, "sinvalid accruedFunding");
            assertGt(leveragePositions[i].marginAfterSettlement, 0, "invalid marginAfterSettlement");
            assertGt(leveragePositions[i].liquidationPrice, 0, "invalid liquidationPrice");
        }
    }

    // Tests multiple getPositionData() function with a token range
    function test_viewer_leverage_positions_range() public {
        vm.prank(admin);
        vaultProxy.setMaxFundingVelocity(0.03e18); // we want to see the funding rates in action for the viewer

        setWethPrice(2200e8);

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 110e18,
            oraclePrice: 2200e8,
            keeperFeeAmount: 0
        });

        setWethPrice(2500e8);

        for (uint256 i = 0; i < 100; i++) {
            announceAndExecuteLeverageOpen({
                traderAccount: alice,
                keeperAccount: keeper,
                margin: 1e18,
                additionalSize: 1e18,
                oraclePrice: 2500e8,
                keeperFeeAmount: 0
            });
        }

        setWethPrice(4000e8);

        skip(1 days); // skewed short slightly, so funding rate should decrease over time

        announceAndExecuteLeverageClose({
            tokenId: 40,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: 4000e8,
            keeperFeeAmount: 0
        });

        announceAndExecuteLeverageClose({
            tokenId: 60,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: 4000e8,
            keeperFeeAmount: 0
        });

        _checkPositionData({tokenFrom: 0, tokenTo: 49});
        _checkPositionData({tokenFrom: 50, tokenTo: 99});
    }

    function test_viewer_flatcoin_tvl() public {
        setWethPrice(2200e8);

        uint256 depositAmount = 100e18;
        uint256 collateralPrice = 2200e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: depositAmount,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        uint256 tvl = viewer.getFlatcoinTVL();
        assertEq(tvl, (depositAmount * collateralPrice * 1e10) / 1e18, "Incorrect TVL");
    }

    function test_viewer_market_skew_percentage_when_no_LP_and_no_leverage_positions() public {
        setWethPrice(2200e8);

        int256 marketSkewPercentage = viewer.getMarketSkewPercentage();

        assertEq(marketSkewPercentage, 0, "Market should be perfectly hedged");
    }

    function test_viewer_market_skew_percentage_stable_skewed() public {
        setWethPrice(2200e8);

        uint256 collateralPrice = 2200e8;
        uint256 depositAmount = 52e18;
        uint256 additionalSize = 48e18;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: depositAmount,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 48e18,
            additionalSize: additionalSize,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        int256 marketSkewPercentage = viewer.getMarketSkewPercentage();

        assertEq(
            marketSkewPercentage,
            _getExpectedSkewPercentage(depositAmount, additionalSize),
            "Market should be 7.69% skewed towards stables"
        );
    }

    function test_viewer_market_skew_percentage_stable_skewed_fully() public {
        setWethPrice(2200e8);

        uint256 depositAmount = 100e18;
        uint256 collateralPrice = 2200e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: depositAmount,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        int256 marketSkewPercentage = viewer.getMarketSkewPercentage();

        assertEq(marketSkewPercentage, -1e18, "Market should be fully skewed towards stables");
    }

    function test_viewer_market_skew_percentage_long_skewed() public {
        setWethPrice(2200e8);

        vm.prank(admin);
        leverageModProxy.setLevTradingFee(0); // ensure that the trading fees going to stable LPs don't impact the result

        uint256 collateralPrice = 2200e8;
        uint256 depositAmount = 48e18;
        uint256 additionalSize = 52e18;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: depositAmount,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 52e18,
            additionalSize: additionalSize,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        int256 marketSkewPercentage = viewer.getMarketSkewPercentage();

        assertEq(
            marketSkewPercentage,
            _getExpectedSkewPercentage(depositAmount, additionalSize),
            "Market should be 8.33% skewed towards longs"
        );
    }

    function test_viewer_market_skew_percentage_long_skewed_fully() public {
        setWethPrice(2200e8);

        vm.startPrank(admin);
        leverageModProxy.setLevTradingFee(0); // ensure that the trading fees going to stable LPs don't impact the result
        vaultProxy.setSkewFractionMax(1.2e18);

        uint256 collateralPrice = 2200e8;
        uint256 depositAmount = 100e18;
        uint256 additionalSize = 120e18;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: depositAmount,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 100e18,
            additionalSize: additionalSize,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        int256 marketSkewPercentage = viewer.getMarketSkewPercentage();

        assertEq(marketSkewPercentage, 0.2e18, "Market should be 20% skewed towards longs");
    }

    function test_viewer_market_skew_percentage_perfectly_hedged() public {
        setWethPrice(2200e8);

        // Disable trading fees so that they don't impact the results
        vm.startPrank(admin);
        stableModProxy.setStableWithdrawFee(0);
        leverageModProxy.setLevTradingFee(0);

        uint256 collateralPrice = 2200e8;
        uint256 depositAmount = 100e18;
        uint256 additionalSize = 100e18;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: depositAmount,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 100e18,
            additionalSize: additionalSize,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        int256 marketSkewPercentage = viewer.getMarketSkewPercentage();

        assertEq(marketSkewPercentage, 0, "Market should be perfectly hedged");
    }

    function _checkPositionData(uint256 tokenFrom, uint256 tokenTo) internal {
        FlatcoinStructs.LeveragePositionData[] memory leveragePositions = viewer.getPositionData(tokenFrom, tokenTo);
        for (uint256 i = 0; i < leveragePositions.length; i++) {
            uint256 tokenId = i + tokenFrom;
            assertEq(leveragePositions[i].tokenId, tokenId, "invalid tokenId burned token");

            try leverageModProxy.ownerOf(tokenId) returns (address) {
                assertEq(leveragePositions[i].tokenId, tokenId, "invalid tokenId");
                assertGt(leveragePositions[i].lastPrice, 0, "invalid lastPrice");
                assertGt(leveragePositions[i].marginDeposited, 0, "invalid marginDeposited");
                assertGt(leveragePositions[i].additionalSize, 0, "invalid additionalSize");
                assertLt(leveragePositions[i].entryCumulativeFunding, 0, "invalid entryCumulativeFunding");
                assertGt(leveragePositions[i].profitLoss, 0, "invalid profitLoss");
                assertGt(leveragePositions[i].accruedFunding, 0, "invalid accruedFunding");
                assertGt(leveragePositions[i].marginAfterSettlement, 0, "invalid marginAfterSettlement");
                assertGt(leveragePositions[i].liquidationPrice, 0, "invalid liquidationPrice");
            } catch {
                // burned token 0 check
                assertEq(leveragePositions[i].lastPrice, 0, "invalid lastPrice burned token");
                assertEq(leveragePositions[i].marginDeposited, 0, "invalid marginDeposited burned token");
                assertEq(leveragePositions[i].additionalSize, 0, "invalid additionalSize burned token");
                assertEq(leveragePositions[i].entryCumulativeFunding, 0, "invalid entryCumulativeFunding burned token");
                assertEq(leveragePositions[i].profitLoss, 0, "invalid profitLoss burned token");
                assertEq(leveragePositions[i].accruedFunding, 0, "sinvalid accruedFunding burned token");
                assertEq(leveragePositions[i].marginAfterSettlement, 0, "invalid marginAfterSettlement burned token");
                assertEq(leveragePositions[i].liquidationPrice, 0, "invalid liquidationPrice burned token");
            }
        }
    }

    function _getExpectedSkewPercentage(uint256 depositAmount, uint256 additionalSize) internal pure returns (int256) {
        return ((int256(additionalSize) - int256(depositAmount)) * 1e18) / int256(depositAmount);
    }
}
