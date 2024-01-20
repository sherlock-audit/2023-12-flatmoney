// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Create2Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/Create2Upgradeable.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {MockPyth} from "pyth-sdk-solidity/MockPyth.sol";
import {IPyth} from "pyth-sdk-solidity/IPyth.sol";

import {Setup} from "./Setup.sol";
import {FlatcoinStructs} from "../../src/libraries/FlatcoinStructs.sol";
import {MockKeeperFee} from "../unit/mocks/MockKeeperFee.sol";
import {PerpMath} from "../../src/libraries/PerpMath.sol";
import {IChainlinkAggregatorV3} from "../../src/interfaces/IChainlinkAggregatorV3.sol";
import {FlatcoinVault} from "../../src/FlatcoinVault.sol";
import {StableModule} from "../../src/StableModule.sol";
import {OracleModule} from "../../src/OracleModule.sol";
import {LeverageModule} from "../../src/LeverageModule.sol";
import {DelayedOrder} from "../../src/DelayedOrder.sol";
import {ILeverageModule} from "../../src/interfaces/ILeverageModule.sol";
import {IStableModule} from "../../src/interfaces/IStableModule.sol";
import {IDelayedOrder} from "../../src/interfaces/IDelayedOrder.sol";
import {IOracleModule} from "../../src/interfaces/IOracleModule.sol";

import "forge-std/Test.sol";
import "forge-std/console2.sol";

abstract contract OrderHelpers is Setup {
    using PerpMath for int256;
    using PerpMath for uint256;

    /********************************************
     *             Helper Functions             *
     ********************************************/

    struct AnnounceAdjustTestData {
        uint256 traderEthBalanceBefore;
        uint256 traderNftBalanceBefore;
        uint256 delayedOrderBalanceBefore;
        uint256 stableCollateralPerShareBefore;
        bool marginIncrease;
        uint256 totalEthRequired;
    }

    struct VerifyLeverageData {
        uint256 nftTotalSupply;
        uint256 traderEthBalance;
        uint256 traderNftBalance;
        uint256 contractNftBalance;
        uint256 keeperBalance;
        uint256 stableCollateralPerShare;
        FlatcoinStructs.PositionSummary positionSummary;
        uint256 oraclePrice;
    }

    // *** Announced stable orders ***

    function announceAndExecuteDeposit(
        address traderAccount,
        address keeperAccount,
        uint256 depositAmount,
        uint256 oraclePrice,
        uint256 keeperFeeAmount
    ) public virtual {
        keeperFeeAmount = keeperFeeAmount > 0 ? keeperFeeAmount : mockKeeperFee.getKeeperFee();

        announceStableDeposit(traderAccount, depositAmount, keeperFeeAmount);

        skip(uint256(vaultProxy.minExecutabilityAge())); // must reach minimum executability time

        executeStableDeposit(keeperAccount, traderAccount, oraclePrice);
    }

    function announceAndExecuteWithdraw(
        address traderAccount,
        address keeperAccount,
        uint256 withdrawAmount,
        uint256 oraclePrice,
        uint256 keeperFeeAmount
    ) public virtual {
        announceStableWithdraw(traderAccount, withdrawAmount, keeperFeeAmount);

        skip(uint256(vaultProxy.minExecutabilityAge())); // must reach minimum executability time

        executeStableWithdraw(keeperAccount, traderAccount, oraclePrice);
    }

    function announceStableDeposit(
        address traderAccount,
        uint256 depositAmount,
        uint256 keeperFeeAmount
    ) public virtual {
        vm.startPrank(traderAccount);
        keeperFeeAmount = keeperFeeAmount > 0 ? keeperFeeAmount : mockKeeperFee.getKeeperFee();
        uint256 traderEthBalance = WETH.balanceOf(traderAccount);
        uint256 traderStableBalance = stableModProxy.balanceOf(traderAccount);
        uint256 stableCollateralPerShareBefore = stableModProxy.stableCollateralPerShare();
        uint256 minAmountOut = 1; // TODO: test this seperately

        // Approve WETH
        WETH.increaseAllowance(address(delayedOrderProxy), depositAmount + keeperFeeAmount);

        // Announce the order
        IDelayedOrder(vaultProxy.moduleAddress(DELAYED_ORDER_KEY)).announceStableDeposit({
            depositAmount: depositAmount,
            minAmountOut: minAmountOut,
            keeperFee: keeperFeeAmount
        });
        FlatcoinStructs.Order memory order = delayedOrderProxy.getAnnouncedOrder(traderAccount);
        {
            FlatcoinStructs.AnnouncedStableDeposit memory stableDeposit = abi.decode(
                order.orderData,
                (FlatcoinStructs.AnnouncedStableDeposit)
            );
            assertEq(stableDeposit.depositAmount, depositAmount, "Incorrect deposit order amount");
            assertEq(stableDeposit.minAmountOut, minAmountOut, "Incorrect deposit order minimum amount out");
        }
        assertEq(
            WETH.balanceOf(traderAccount),
            traderEthBalance - depositAmount - keeperFeeAmount,
            "Incorrect trader WETH balance after announce"
        );
        assertEq(
            traderStableBalance,
            stableModProxy.balanceOf(traderAccount),
            "No LP tokens should have been minted yet"
        );
        assertApproxEqAbs(
            stableCollateralPerShareBefore,
            stableModProxy.stableCollateralPerShare(),
            1e6, // rounding error only
            "stableCollateralPerShare changed after announce"
        );
        assertGt(order.keeperFee, 0, "keeper fee amount not > 0");
        assertEq(uint256(order.orderType), uint256(FlatcoinStructs.OrderType.StableDeposit), "Order doesn't exist");
        vm.stopPrank();
    }

    function announceStableWithdraw(
        address traderAccount,
        uint256 withdrawAmount,
        uint256 keeperFeeAmount
    ) public virtual {
        vm.startPrank(traderAccount);
        keeperFeeAmount = keeperFeeAmount > 0 ? keeperFeeAmount : mockKeeperFee.getKeeperFee();
        uint256 vaultEthBalance = WETH.balanceOf(address(vaultProxy));
        uint256 traderEthBalance = WETH.balanceOf(traderAccount);
        uint256 traderStableBalance = stableModProxy.balanceOf(traderAccount);
        uint256 stableCollateralPerShareBefore = stableModProxy.stableCollateralPerShare();
        uint256 minAmountOut = 1; // TODO: test this separately

        // Announce the order
        IDelayedOrder(vaultProxy.moduleAddress(DELAYED_ORDER_KEY)).announceStableWithdraw({
            withdrawAmount: withdrawAmount,
            minAmountOut: minAmountOut,
            keeperFee: keeperFeeAmount
        });
        FlatcoinStructs.Order memory order = delayedOrderProxy.getAnnouncedOrder(traderAccount);
        {
            FlatcoinStructs.AnnouncedStableWithdraw memory stableWithdraw = abi.decode(
                order.orderData,
                (FlatcoinStructs.AnnouncedStableWithdraw)
            );
            assertEq(stableWithdraw.withdrawAmount, withdrawAmount, "Incorrect withdraw order amount");
            assertEq(stableWithdraw.minAmountOut, minAmountOut, "Incorrect withdraw order minimum amount out");
        }

        assertEq(
            stableModProxy.balanceOf(traderAccount),
            traderStableBalance,
            "LP tokens should not have been deducted from the trader's balance yet"
        );
        assertEq(WETH.balanceOf(traderAccount), traderEthBalance, "Trader WETH balance should not have changed yet");
        assertEq(
            stableModProxy.balanceOf(address(delayedOrderProxy)),
            0,
            "Delayed Order LP balance shouldn't have changed"
        );
        assertEq(stableModProxy.getLockedAmount(traderAccount), withdrawAmount, "Stable LP not locked on announce");
        assertEq(traderEthBalance, WETH.balanceOf(traderAccount), "Collateral balance changed for trader on announce"); // no collateral change for the trader
        assertApproxEqAbs(
            stableCollateralPerShareBefore,
            stableModProxy.stableCollateralPerShare(),
            1e6, // rounding error only
            "stableCollateralPerShare changed"
        );
        assertEq(vaultEthBalance, WETH.balanceOf(address(vaultProxy)), "Vault WETH balance changed on announce");
        assertGt(order.keeperFee, 0, "keeper fee amount not > 0");
        assertEq(uint256(order.orderType), uint256(FlatcoinStructs.OrderType.StableWithdraw), "Order doesn't exist");

        vm.stopPrank();
    }

    function executeStableDeposit(address keeperAccount, address traderAccount, uint256 oraclePrice) public virtual {
        // Execute the user's pending deposit
        uint256 lpTotalSupply = stableModProxy.totalSupply();
        uint256 traderStableBalance = stableModProxy.balanceOf(traderAccount);
        uint256 keeperBalanceBefore = WETH.balanceOf(keeperAccount);

        uint256 stableCollateralPerShareBefore = uint256(_getStableCollateralPerShare(oraclePrice * 1e10));

        FlatcoinStructs.Order memory order = delayedOrderProxy.getAnnouncedOrder(traderAccount);
        FlatcoinStructs.AnnouncedStableDeposit memory stableDeposit = abi.decode(
            order.orderData,
            (FlatcoinStructs.AnnouncedStableDeposit)
        );
        uint256 depositAmount = stableDeposit.depositAmount;

        vm.startPrank(keeperAccount);

        bytes[] memory priceUpdateData = getPriceUpdateData(oraclePrice);

        delayedOrderProxy.executeOrder{value: 1}(traderAccount, priceUpdateData);

        assertEq(
            keeperBalanceBefore + order.keeperFee,
            WETH.balanceOf(keeperAccount),
            "Incorrect amount sent to keeper after deposit execution"
        );

        assertGt(order.keeperFee, 0, "keeper fee amount not > 0");

        assertApproxEqAbs(
            stableCollateralPerShareBefore,
            stableModProxy.stableCollateralPerShare(),
            1e6, // rounding error only
            "stableCollateralPerShare changed after deposit execution"
        );
        assertEq(
            stableModProxy.balanceOf(traderAccount),
            (traderStableBalance +
                (depositAmount * (10 ** stableModProxy.decimals())) /
                stableCollateralPerShareBefore),
            "Incorrect deposit tokens minted to trader after deposit execution"
        );
        assertEq(
            stableModProxy.totalSupply(),
            lpTotalSupply + ((depositAmount * (10 ** stableModProxy.decimals())) / stableCollateralPerShareBefore),
            "incorrect LP total supply after deposit execution"
        );

        vm.stopPrank();
    }

    function executeStableWithdraw(address keeperAccount, address traderAccount, uint256 oraclePrice) public virtual {
        uint256 lpTotalSupply = stableModProxy.totalSupply();
        uint256 keeperBalanceBefore = WETH.balanceOf(keeperAccount);

        uint256 stableCollateralPerShareBefore = stableModProxy.stableCollateralPerShare();
        FlatcoinStructs.Order memory order = delayedOrderProxy.getAnnouncedOrder(traderAccount);
        FlatcoinStructs.AnnouncedStableWithdraw memory stableWithdraw = abi.decode(
            order.orderData,
            (FlatcoinStructs.AnnouncedStableWithdraw)
        );
        uint256 withdrawAmount = stableWithdraw.withdrawAmount;
        uint256 traderWethBalanceBefore = WETH.balanceOf(traderAccount);
        uint256 traderLPBalanceBefore = stableModProxy.balanceOf(traderAccount);

        // Execute the user's pending withdrawal
        {
            vm.startPrank(keeperAccount);

            bytes[] memory priceUpdateData = getPriceUpdateData(oraclePrice);

            delayedOrderProxy.executeOrder{value: 1}(traderAccount, priceUpdateData);

            uint256 expectedAmountOut = (withdrawAmount * stableCollateralPerShareBefore) /
                (10 ** stableModProxy.decimals());

            uint256 withdrawFee;
            if (stableModProxy.totalSupply() > 0) {
                // don't apply the withdrawal fee on the last withdrawal
                withdrawFee = (stableModProxy.stableWithdrawFee() * expectedAmountOut) / 1e18;
            }

            uint256 traderWethBalanceAfter = WETH.balanceOf(traderAccount);

            assertEq(
                expectedAmountOut - order.keeperFee - withdrawFee,
                traderWethBalanceAfter - traderWethBalanceBefore,
                "incorrect collateral tokens transferred to trader after execute"
            );
        }

        if (stableModProxy.totalSupply() > 0) {
            assertLe(
                stableCollateralPerShareBefore,
                stableModProxy.stableCollateralPerShare(), // can be higher if withdraw fees are enabled
                "stableCollateralPerShare changed after execute"
            );
        } else {
            assertEq(
                stableModProxy.stableCollateralPerShare(),
                1e18,
                "stableCollateralPerShare should be 1e18 after final withdraw"
            );
        }

        assertEq(stableModProxy.getLockedAmount(traderAccount), 0, "Stable LP not unlocked after execute");
        assertEq(
            stableModProxy.balanceOf(traderAccount),
            traderLPBalanceBefore - withdrawAmount,
            "Stable LP not deducted from trader after execute"
        );
        assertEq(
            stableModProxy.balanceOf(address(delayedOrderProxy)),
            0,
            "Stable LP shouldn't be transferred to delayed order"
        );
        assertEq(
            keeperBalanceBefore + order.keeperFee,
            WETH.balanceOf(keeperAccount),
            "invalid keeper fee transfer after execute"
        );
        assertEq(
            stableModProxy.balanceOf(address(delayedOrderProxy)),
            0,
            "not all LP tokens are out of DelayedOrder contract after execute"
        );
        assertEq(
            lpTotalSupply,
            stableModProxy.totalSupply() + withdrawAmount,
            "incorrect LP total supply after execute"
        );
        assertGt(order.keeperFee, 0, "keeper fee amount not > 0");

        vm.stopPrank();
    }

    // *** Announced leverage orders ***

    function announceAndExecuteLeverageOpen(
        address traderAccount,
        address keeperAccount,
        uint256 margin,
        uint256 additionalSize,
        uint256 oraclePrice,
        uint256 keeperFeeAmount
    ) public virtual returns (uint256 tokenId) {
        announceOpenLeverage(traderAccount, margin, additionalSize, keeperFeeAmount);

        skip(uint256(vaultProxy.minExecutabilityAge())); // must reach minimum executability time

        int256 fundingRateBefore = vaultProxy.getCurrentFundingRate();

        tokenId = executeOpenLeverage(keeperAccount, traderAccount, oraclePrice);

        assertEq(
            vaultProxy.getCurrentFundingRate(),
            fundingRateBefore,
            "Funding rate should not change immediately after adjustment"
        );
    }

    function announceAndExecuteLeverageAdjust(
        uint256 tokenId,
        address traderAccount,
        address keeperAccount,
        int256 marginAdjustment,
        int256 additionalSizeAdjustment,
        uint256 oraclePrice,
        uint256 keeperFeeAmount
    ) public returns (uint256 tradeFee) {
        announceAdjustLeverage(traderAccount, tokenId, marginAdjustment, additionalSizeAdjustment, keeperFeeAmount);

        skip(uint256(vaultProxy.minExecutabilityAge())); // must reach minimum executability time

        int256 fundingRateBefore = vaultProxy.getCurrentFundingRate();

        tradeFee = executeAdjustLeverage(keeperAccount, traderAccount, oraclePrice);

        assertEq(
            vaultProxy.getCurrentFundingRate(),
            fundingRateBefore,
            "Funding rate should not change immediately after adjustment"
        );
    }

    function announceAndExecuteLeverageClose(
        uint256 tokenId,
        address traderAccount,
        address keeperAccount,
        uint256 oraclePrice,
        uint256 keeperFeeAmount
    ) public virtual {
        announceCloseLeverage(traderAccount, tokenId, keeperFeeAmount);

        skip(uint256(vaultProxy.minExecutabilityAge())); // must reach minimum executability time

        int256 fundingRateBefore = vaultProxy.getCurrentFundingRate();

        executeCloseLeverage(keeperAccount, traderAccount, oraclePrice);

        assertEq(
            fundingRateBefore,
            vaultProxy.getCurrentFundingRate(),
            "Funding rate should not change immediately after close"
        );
    }

    function announceOpenLeverage(
        address traderAccount,
        uint256 margin,
        uint256 additionalSize,
        uint256 keeperFeeAmount
    ) public virtual {
        vm.startPrank(traderAccount);
        keeperFeeAmount = keeperFeeAmount > 0 ? keeperFeeAmount : mockKeeperFee.getKeeperFee();
        uint256 traderEthBalance = WETH.balanceOf(traderAccount);
        uint256 traderNftBalance = leverageModProxy.balanceOf(traderAccount);
        uint256 stableCollateralPerShareBefore = stableModProxy.stableCollateralPerShare();

        // Approve WETH
        uint256 tradeFee = (leverageModProxy.levTradingFee() * additionalSize) / 1e18;
        WETH.increaseAllowance(address(delayedOrderProxy), margin + keeperFeeAmount + tradeFee);

        // Announce the order
        (uint256 maxFillPrice, ) = oracleModProxy.getPrice();
        delayedOrderProxy.announceLeverageOpen(
            margin,
            additionalSize,
            maxFillPrice + 100, // add some slippage
            keeperFeeAmount
        );
        FlatcoinStructs.Order memory order = delayedOrderProxy.getAnnouncedOrder(traderAccount);
        {
            FlatcoinStructs.AnnouncedLeverageOpen memory leverageOpen = abi.decode(
                order.orderData,
                (FlatcoinStructs.AnnouncedLeverageOpen)
            );
            assertEq(leverageOpen.margin, margin, "Announce open order margin incorrect");
            assertEq(leverageOpen.additionalSize, additionalSize, "Announce open order additionalSize incorrect");
            assertEq(leverageOpen.maxFillPrice - 100, maxFillPrice, "Announce open order invalid maximum fill price");
        }

        assertEq(order.keeperFee, keeperFeeAmount, "Incorrect keeper fee in order");
        assertGt(order.executableAtTime, block.timestamp, "Order executability should be after current time");
        assertEq(
            WETH.balanceOf(traderAccount),
            traderEthBalance - margin - keeperFeeAmount - tradeFee,
            "Trader WETH balance incorrect after announcement"
        );
        assertEq(
            traderNftBalance,
            leverageModProxy.balanceOf(traderAccount),
            "Trader should not have NFT minted after announcement"
        ); // no tokens minted yet
        assertEq(
            stableCollateralPerShareBefore,
            stableModProxy.stableCollateralPerShare(),
            "Stable collateral per share has not remained the same after announce"
        );
        assertGt(order.keeperFee, 0, "Keeper fee should not be 0");
        assertEq(uint256(order.orderType), uint256(FlatcoinStructs.OrderType.LeverageOpen), "Order doesn't exist");
        vm.stopPrank();
    }

    function announceAdjustLeverage(
        address traderAccount,
        uint256 tokenId,
        int256 marginAdjustment,
        int256 additionalSizeAdjustment,
        uint256 keeperFeeAmount
    ) public {
        vm.startPrank(traderAccount);

        keeperFeeAmount = keeperFeeAmount > 0 ? keeperFeeAmount : mockKeeperFee.getKeeperFee();
        bool sizeIncrease = additionalSizeAdjustment >= 0;

        AnnounceAdjustTestData memory testData = AnnounceAdjustTestData({
            traderEthBalanceBefore: WETH.balanceOf(traderAccount),
            traderNftBalanceBefore: leverageModProxy.balanceOf(traderAccount),
            delayedOrderBalanceBefore: WETH.balanceOf(address(delayedOrderProxy)),
            stableCollateralPerShareBefore: stableModProxy.stableCollateralPerShare(),
            marginIncrease: marginAdjustment > 0,
            totalEthRequired: uint256(marginAdjustment) +
                keeperFeeAmount +
                (leverageModProxy.levTradingFee() *
                    (sizeIncrease ? uint256(additionalSizeAdjustment) : uint256(additionalSizeAdjustment * -1))) /
                1e18 // margin + keeper fee + trade fee
        });

        if (testData.marginIncrease) {
            WETH.increaseAllowance(address(delayedOrderProxy), testData.totalEthRequired);
        }

        (uint256 modifiedFillPrice, ) = oracleModProxy.getPrice();
        uint256 fillPrice = sizeIncrease ? modifiedFillPrice + 100 : modifiedFillPrice - 100; // not sure why it's needed
        delayedOrderProxy.announceLeverageAdjust(
            tokenId,
            marginAdjustment,
            additionalSizeAdjustment,
            fillPrice,
            keeperFeeAmount
        );

        FlatcoinStructs.Order memory order = delayedOrderProxy.getAnnouncedOrder(traderAccount);
        FlatcoinStructs.AnnouncedLeverageAdjust memory leverageAdjust = abi.decode(
            order.orderData,
            (FlatcoinStructs.AnnouncedLeverageAdjust)
        );

        assertEq(leverageAdjust.tokenId, tokenId, "Announce adjust order invalid token ID");
        assertTrue(leverageModProxy.isLocked(tokenId), "Position token not locked");
        assertEq(leverageAdjust.marginAdjustment, marginAdjustment, "Announce adjust order invalid margin adjustment");
        assertEq(
            leverageAdjust.additionalSizeAdjustment,
            additionalSizeAdjustment,
            "Announce adjust order invalid additional size adjustment"
        );
        assertEq(
            sizeIncrease ? leverageAdjust.fillPrice - 100 : leverageAdjust.fillPrice + 100,
            modifiedFillPrice,
            "Announce adjust order invalid fill price"
        );
        assertEq(order.keeperFee, keeperFeeAmount, "Incorrect keeper fee in announce adjust order");
        assertGt(
            order.executableAtTime,
            block.timestamp,
            "Announce adjust order executability should be after current time"
        );
        assertGt(order.keeperFee, 0, "Keeper fee should not be 0");
        assertEq(uint256(order.orderType), uint256(FlatcoinStructs.OrderType.LeverageAdjust), "Order doesn't exist");

        assertEq(
            testData.traderNftBalanceBefore,
            leverageModProxy.balanceOf(traderAccount),
            "Trader NFT balance incorrect after adjust announcement"
        );
        assertEq(
            testData.stableCollateralPerShareBefore,
            stableModProxy.stableCollateralPerShare(),
            "Stable collateral per share has not remained the same after adjust announcement"
        );

        if (testData.marginIncrease) {
            assertEq(
                testData.delayedOrderBalanceBefore + testData.totalEthRequired,
                WETH.balanceOf(address(delayedOrderProxy)),
                "DelayedOrder WETH balance incorrect after adjust announcement"
            );
            assertEq(
                testData.traderEthBalanceBefore - testData.totalEthRequired,
                WETH.balanceOf(traderAccount),
                "Trader WETH balance incorrect after adjust announcement"
            );
        } else {
            assertEq(
                testData.delayedOrderBalanceBefore,
                WETH.balanceOf(address(delayedOrderProxy)),
                "DelayedOrder WETH balance incorrect after adjust announcement"
            );
            assertEq(
                testData.traderEthBalanceBefore,
                WETH.balanceOf(traderAccount),
                "Trader WETH balance incorrect after adjust announcement"
            );
        }

        vm.stopPrank();
    }

    function announceCloseLeverage(address traderAccount, uint256 tokenId, uint256 keeperFeeAmount) public virtual {
        vm.startPrank(traderAccount);
        keeperFeeAmount = keeperFeeAmount > 0 ? keeperFeeAmount : mockKeeperFee.getKeeperFee();
        uint256 traderEthBalanceBefore = WETH.balanceOf(traderAccount);
        uint256 stableCollateralPerShareBefore = stableModProxy.stableCollateralPerShare();
        int256 positionMargin = leverageModProxy.getPositionSummary(tokenId).marginAfterSettlement;

        (uint256 minFillPrice, ) = oracleModProxy.getPrice();

        // Announce the order
        delayedOrderProxy.announceLeverageClose(
            tokenId,
            minFillPrice - 100, // add some slippage
            keeperFeeAmount
        );
        FlatcoinStructs.Order memory order = delayedOrderProxy.getAnnouncedOrder(traderAccount);
        {
            FlatcoinStructs.AnnouncedLeverageClose memory leverageClose = abi.decode(
                order.orderData,
                (FlatcoinStructs.AnnouncedLeverageClose)
            );

            assertTrue(leverageModProxy.isLocked(leverageClose.tokenId), "Position token not locked");
            assertEq(leverageClose.tokenId, tokenId, "Announce close order invalid token ID");
            assertEq(leverageClose.minFillPrice + 100, minFillPrice, "Announce close order invalid minimum fill price");
        }

        assertEq(WETH.balanceOf(traderAccount), traderEthBalanceBefore, "Trader WETH balance should not have changed");
        assertEq(
            stableCollateralPerShareBefore,
            stableModProxy.stableCollateralPerShare(),
            "Stable collateral per share has not remained the same after announce"
        );
        assertGt(positionMargin, 0, "Position margin isn't > 0 after announce");
        assertGt(order.keeperFee, 0, "Keeper fee should not be 0");
        assertEq(uint256(order.orderType), uint256(FlatcoinStructs.OrderType.LeverageClose), "Order doesn't exist");
        vm.stopPrank();
    }

    function executeOpenLeverage(
        address keeperAccount,
        address traderAccount,
        uint256 oraclePrice
    ) public virtual returns (uint256 tokenId) {
        uint256 traderNftBalanceBefore = leverageModProxy.balanceOf(traderAccount);
        uint256 keeperBalanceBefore = WETH.balanceOf(keeperAccount);
        uint256 stableCollateralPerShareBefore = uint256(_getStableCollateralPerShare(oraclePrice * 1e10));

        FlatcoinStructs.Order memory order = delayedOrderProxy.getAnnouncedOrder(traderAccount);
        FlatcoinStructs.AnnouncedLeverageOpen memory leverageOpen = abi.decode(
            order.orderData,
            (FlatcoinStructs.AnnouncedLeverageOpen)
        );

        bytes[] memory priceUpdateData = getPriceUpdateData(oraclePrice);

        // Execute the user's pending deposit
        vm.prank(keeperAccount);

        delayedOrderProxy.executeOrder{value: 1}(traderAccount, priceUpdateData);
        uint256 traderBalance = leverageModProxy.balanceOf(traderAccount);
        tokenId = leverageModProxy.tokenOfOwnerByIndex(traderAccount, traderBalance - 1);

        {
            uint256 tradingFee = (leverageModProxy.levTradingFee() * leverageOpen.additionalSize) / 1e18;
            uint256 totalSupply = stableModProxy.totalSupply();

            if (totalSupply > 0) {
                assertApproxEqAbs(
                    stableCollateralPerShareBefore + ((tradingFee * (10 ** stableModProxy.decimals())) / totalSupply),
                    stableModProxy.stableCollateralPerShare(), // there should be some additional value in the stable LPs from earned trading fee
                    1e6, // rounding error only
                    "stableCollateralPerShare incorrect after trade"
                );
            }
        }

        assertEq(traderNftBalanceBefore, leverageModProxy.balanceOf(traderAccount) - 1, "Position NFT not minted");
        {
            FlatcoinStructs.PositionSummary memory positionSummary = leverageModProxy.getPositionSummary(tokenId);
            FlatcoinStructs.Position memory position = vaultProxy.getPosition(tokenId);
            (uint256 price, ) = oracleModProxy.getPrice();
            assertEq(position.lastPrice, price, "Position last price incorrect");
            assertEq(
                position.lastPrice,
                oraclePrice * 1e10, // convert to 18 decimals
                "Position last price incorrect"
            );
            assertEq(position.marginDeposited, leverageOpen.margin, "Position margin deposited incorrect");
            assertEq(position.additionalSize, leverageOpen.additionalSize, "Position additional size incorrect");
            assertEq(
                position.entryCumulativeFunding,
                vaultProxy.cumulativeFundingRate(),
                "Position entry cumulative funding rate incorrect"
            );
            assertEq(
                uint256(positionSummary.marginAfterSettlement),
                leverageOpen.margin,
                "Position margin after settlement incorrect"
            );
            assertEq(uint256(positionSummary.profitLoss), 0, "Position PnL should be 0");
            assertEq(uint256(positionSummary.accruedFunding), 0, "Position accrued funding should be 0");
        }
        {
            FlatcoinStructs.Position memory position = vaultProxy.getPosition(tokenId);
            assertEq(
                position.lastPrice,
                oraclePrice * 1e10, // convert to 18 decimals
                "Position last price invalid"
            );
            assertEq(position.additionalSize, leverageOpen.additionalSize, "Position additionalSize invalid");
            assertEq(position.marginDeposited, leverageOpen.margin, "Position marginDeposited invalid");
        }
        assertEq(
            keeperBalanceBefore + order.keeperFee,
            WETH.balanceOf(keeperAccount),
            "Incorrect amount sent to keeper after execution"
        );
        assertGt(order.keeperFee, 0, "keeper fee amount not > 0");
    }

    function executeAdjustLeverage(
        address keeperAccount,
        address traderAccount,
        uint256 oraclePrice
    ) public returns (uint256 tradeFee) {
        FlatcoinStructs.Order memory order = delayedOrderProxy.getAnnouncedOrder(traderAccount);
        FlatcoinStructs.AnnouncedLeverageAdjust memory leverageAdjust = abi.decode(
            order.orderData,
            (FlatcoinStructs.AnnouncedLeverageAdjust)
        );
        uint256 additionalSizeBefore = vaultProxy.getPosition(leverageAdjust.tokenId).additionalSize;

        VerifyLeverageData memory before = VerifyLeverageData({
            nftTotalSupply: leverageModProxy.totalSupply(),
            traderEthBalance: WETH.balanceOf(traderAccount),
            traderNftBalance: leverageModProxy.balanceOf(traderAccount),
            contractNftBalance: leverageModProxy.balanceOf(address(delayedOrderProxy)),
            keeperBalance: WETH.balanceOf(keeperAccount),
            stableCollateralPerShare: uint256(_getStableCollateralPerShare(oraclePrice * 1e10)),
            positionSummary: leverageModProxy.getPositionSummary(leverageAdjust.tokenId),
            oraclePrice: _oraclePrice()
        });

        vm.startPrank(keeperAccount);
        delayedOrderProxy.executeOrder{value: 1}(traderAccount, getPriceUpdateData(oraclePrice));

        {
            uint256 totalSupply = stableModProxy.totalSupply();

            assertApproxEqAbs(
                before.stableCollateralPerShare +
                    ((leverageAdjust.tradeFee * (10 ** stableModProxy.decimals())) / totalSupply),
                stableModProxy.stableCollateralPerShare(), // there should be some additional value in the stable LPs from earned trading fee
                1e6, // rounding error only
                "stableCollateralPerShare incorrect after execute adjust"
            );
        }

        if (leverageAdjust.marginAdjustment > 0) {
            assertEq(
                before.traderEthBalance,
                WETH.balanceOf(traderAccount),
                "Trader collateral balance not same when margin adjustment > 0 after execute adjust"
            );
        } else {
            assertEq(
                before.traderEthBalance + uint256(leverageAdjust.marginAdjustment * -1),
                WETH.balanceOf(traderAccount),
                "Incorrect amount sent to trader after execute adjust"
            );
        }

        assertFalse(
            leverageModProxy.isLocked(leverageAdjust.tokenId),
            "Position token still locked after execute adjust"
        );
        assertEq(
            before.traderNftBalance,
            leverageModProxy.balanceOf(traderAccount),
            "Position NFT balance changed after execute adjust"
        );
        assertEq(
            before.nftTotalSupply,
            leverageModProxy.totalSupply(),
            "NFT Total supply didn't remain the same after adjust"
        );

        {
            FlatcoinStructs.Position memory position = vaultProxy.getPosition(leverageAdjust.tokenId);

            assertEq(
                position.marginDeposited,
                uint256(
                    before.positionSummary.marginAfterSettlement +
                        (
                            (leverageAdjust.marginAdjustment > 0)
                                ? leverageAdjust.marginAdjustment
                                : leverageAdjust.marginAdjustment - int256(leverageAdjust.totalFee)
                        )
                ),
                "New margin deposited should have been set as: margin after settlement + margin delta"
            );
            assertEq(
                position.additionalSize,
                uint256(int256(additionalSizeBefore) + leverageAdjust.additionalSizeAdjustment),
                "Position new additional size incorrect after adjust"
            );
            // we account fees only when withdrawing margin, as in this case they're taken from existing margin and affect marginAfterSettlement
            uint256 feesToAccount = leverageAdjust.marginAdjustment <= 0 ? leverageAdjust.totalFee : 0;
            assertApproxEqAbs(
                before.positionSummary.marginAfterSettlement + leverageAdjust.marginAdjustment - int256(feesToAccount),
                leverageModProxy.getPositionSummary(leverageAdjust.tokenId).marginAfterSettlement,
                1e6, // Rounding error only.
                "Margin after settlement should be the same before and after adjustment"
            );
        }

        assertEq(
            before.keeperBalance + order.keeperFee,
            WETH.balanceOf(keeperAccount),
            "Incorrect amount sent to keeper after adjust"
        );
        assertGt(order.keeperFee, 0, "Keeper fee amount not > 0");

        tradeFee = leverageAdjust.tradeFee;
    }

    function executeCloseLeverage(
        address keeperAccount,
        address traderAccount,
        uint256 oraclePrice
    ) public virtual returns (int256 settledMargin) {
        FlatcoinStructs.Order memory order = delayedOrderProxy.getAnnouncedOrder(traderAccount);
        FlatcoinStructs.AnnouncedLeverageClose memory leverageClose = abi.decode(
            order.orderData,
            (FlatcoinStructs.AnnouncedLeverageClose)
        );
        uint256 additionalSize = vaultProxy.getPosition(leverageClose.tokenId).additionalSize;

        VerifyLeverageData memory before = VerifyLeverageData({
            nftTotalSupply: leverageModProxy.totalSupply(),
            traderEthBalance: WETH.balanceOf(traderAccount),
            traderNftBalance: leverageModProxy.balanceOf(traderAccount),
            contractNftBalance: leverageModProxy.balanceOf(address(delayedOrderProxy)),
            keeperBalance: WETH.balanceOf(keeperAccount),
            stableCollateralPerShare: uint256(_getStableCollateralPerShare(oraclePrice * 1e10)),
            positionSummary: leverageModProxy.getPositionSummary(leverageClose.tokenId),
            oraclePrice: _oraclePrice()
        });

        uint256 tradeFee = (leverageModProxy.levTradingFee() * additionalSize) / 1e18;

        bytes[] memory priceUpdateData = getPriceUpdateData(oraclePrice);

        {
            // Execute order doesn't have any return data so we need to try and estimate the settled margin
            // in the position by the trader's WETH balance before and after the transaction execution
            uint256 traderEthBalanceBefore = WETH.balanceOf(traderAccount);
            vm.startPrank(keeperAccount);
            delayedOrderProxy.executeOrder{value: 1}(traderAccount, priceUpdateData);
            uint256 traderEthBalanceAfter = WETH.balanceOf(traderAccount);
            settledMargin =
                int256(traderEthBalanceAfter) -
                int256(traderEthBalanceBefore) +
                int256(order.keeperFee) +
                int(tradeFee);
        }

        {
            FlatcoinStructs.PositionSummary memory positionSummary = leverageModProxy.getPositionSummary(
                leverageClose.tokenId
            );
            assertEq(positionSummary.profitLoss, 0, "Profit loss isn't 0 after close");
            assertEq(positionSummary.accruedFunding, 0, "Accrued funding loss isn't 0 after close");
            assertEq(positionSummary.marginAfterSettlement, 0, "Margin after settlement loss isn't 0 after close");
        }

        assertApproxEqAbs(
            before.stableCollateralPerShare +
                ((tradeFee * (10 ** stableModProxy.decimals())) / stableModProxy.totalSupply()),
            stableModProxy.stableCollateralPerShare(), // there should be some additional value in the stable LPs from earned trading fee
            1e6, // rounding error only
            "stableCollateralPerShare incorrect after close leverage"
        );

        assertEq(
            before.traderEthBalance,
            WETH.balanceOf(traderAccount) -
                (
                    before.positionSummary.marginAfterSettlement > 0
                        ? uint256(before.positionSummary.marginAfterSettlement) - order.keeperFee - tradeFee
                        : 0
                ),
            "Trader WETH balance wrong after close"
        );
        assertEq(
            before.traderNftBalance - 1,
            leverageModProxy.balanceOf(traderAccount),
            "Position NFT still assigned to the trader after burning"
        );
        assertEq(
            before.nftTotalSupply - 1,
            leverageModProxy.totalSupply(),
            "ERC721 token supply not reduced after burn"
        );
        assertEq(
            uint256(settledMargin),
            uint256(before.positionSummary.marginAfterSettlement),
            "Settled margin incorrect after close"
        );

        assertEq(
            before.keeperBalance + order.keeperFee,
            WETH.balanceOf(keeperAccount),
            "Keeper WETH balance wrong after close"
        );
        bool positionZero = vaultProxy.getPosition(leverageClose.tokenId).additionalSize > 0 ||
            vaultProxy.getPosition(leverageClose.tokenId).lastPrice > 0 ||
            vaultProxy.getPosition(leverageClose.tokenId).entryCumulativeFunding > 0 ||
            vaultProxy.getPosition(leverageClose.tokenId).marginDeposited > 0
            ? false
            : true;
        assertEq(positionZero, true, "Position data isn't 0 after close");
        assertEq(before.nftTotalSupply, leverageModProxy.totalSupply() + 1, "ERC721 not burned after close");
        assertGt(order.keeperFee, 0, "keeper fee amount not > 0");

        vm.stopPrank();
    }

    function announceAndExecuteDepositAndLeverageOpen(
        address traderAccount,
        address keeperAccount,
        uint256 depositAmount,
        uint256 margin,
        uint256 additionalSize,
        uint256 oraclePrice,
        uint256 keeperFeeAmount
    ) public virtual returns (uint256 tokenId) {
        // Disable funding rates.
        vm.startPrank(admin);
        vaultProxy.setMaxFundingVelocity(0);

        vm.startPrank(traderAccount);

        announceAndExecuteDeposit({
            traderAccount: traderAccount,
            keeperAccount: keeperAccount,
            depositAmount: depositAmount,
            oraclePrice: oraclePrice,
            keeperFeeAmount: keeperFeeAmount
        });

        tokenId = announceAndExecuteLeverageOpen({
            traderAccount: traderAccount,
            keeperAccount: keeperAccount,
            margin: margin,
            additionalSize: additionalSize,
            oraclePrice: oraclePrice,
            keeperFeeAmount: keeperFeeAmount
        });

        // Enable funding rates.
        vm.startPrank(admin);
        vaultProxy.setMaxFundingVelocity(0.03e18);

        vm.stopPrank();
    }

    // *** Limit orders ***

    function announceAndExecuteLimitClose(
        uint256 tokenId,
        address traderAccount,
        address keeperAccount,
        uint256 priceLowerThreshold,
        uint256 priceUpperThreshold,
        uint256 oraclePrice,
        uint256 keeperFeeAmount
    ) public virtual {
        uint256 keeperWethBalanceBefore = WETH.balanceOf(keeperAccount);
        uint256 traderWethBalanceBefore = WETH.balanceOf(traderAccount);

        vm.startPrank(alice);

        limitOrderProxy.announceLimitOrder({
            tokenId: tokenId,
            priceLowerThreshold: priceLowerThreshold,
            priceUpperThreshold: priceUpperThreshold
        });

        FlatcoinStructs.Order memory order = limitOrderProxy.getLimitOrder(tokenId);
        assertEq(uint256(order.orderType), uint256(FlatcoinStructs.OrderType.LimitClose));
        assertEq(order.keeperFee, 0, "Limit order keeper fee not 0"); // limit orders have no keeper fee
        assertGt(keeperFeeAmount, 0, "keeper fee amount not > 0");
        assertEq(order.executableAtTime, block.timestamp + vaultProxy.minExecutabilityAge());
        {
            FlatcoinStructs.LimitClose memory limitClose = abi.decode(order.orderData, (FlatcoinStructs.LimitClose));
            assertEq(limitClose.priceLowerThreshold, priceLowerThreshold);
            assertEq(limitClose.priceUpperThreshold, priceUpperThreshold);
            assertEq(limitClose.tokenId, tokenId);
        }

        setWethPrice(oraclePrice);
        int256 settledMargin = leverageModProxy.getPositionSummary(tokenId).marginAfterSettlement;
        uint256 tradeFee;
        {
            FlatcoinStructs.Position memory position = vaultProxy.getPosition(tokenId);
            tradeFee = (leverageModProxy.levTradingFee() * position.additionalSize) / 1e18;
        }

        assertGt(settledMargin, 0, "Settled margin should be > 0 before limit close execution");

        skip(uint256(vaultProxy.minExecutabilityAge()));

        bytes[] memory priceUpdateData = getPriceUpdateData(oraclePrice);

        vm.startPrank(keeper);

        limitOrderProxy.executeLimitOrder{value: 1}(tokenId, priceUpdateData);

        assertEq(
            keeperWethBalanceBefore + keeperFeeAmount,
            WETH.balanceOf(keeperAccount),
            "Incorrect amount sent to keeper after limit close execution"
        );
        assertGt(
            WETH.balanceOf(traderAccount),
            traderWethBalanceBefore,
            "Trader WETH balance should have increased after limit close execution"
        );

        assertEq(
            traderWethBalanceBefore + uint256(settledMargin) - tradeFee - keeperFeeAmount,
            WETH.balanceOf(traderAccount),
            "Trader WETH balance incorrect after limit close execution"
        );

        order = limitOrderProxy.getLimitOrder(tokenId);

        assertEq(uint256(order.orderType), 0);
        assertEq(order.keeperFee, 0);
        assertEq(order.executableAtTime, 0);
    }

    function _getStableCollateralPerShare(uint256 price) internal view returns (uint256 collateralPerShare) {
        uint256 totalSupply = stableModProxy.totalSupply();

        if (totalSupply > 0) {
            FlatcoinStructs.VaultSummary memory vaultSummary = vaultProxy.getVaultSummary();

            FlatcoinStructs.MarketSummary memory marketSummary = PerpMath._getMarketSummaryLongs(
                vaultSummary,
                vaultProxy.maxFundingVelocity(),
                vaultProxy.maxVelocitySkew(),
                price
            );

            int256 netTotal = marketSummary.profitLossTotalByLongs + marketSummary.accruedFundingTotalByLongs;

            // The flatcoin LPs are the counterparty to the leverage traders.
            // So when the traders win, the flatcoin LPs lose and vice versa.
            // Therefore we subtract the leverage trader profits and add the losses
            int256 totalAfterSettlement = int256(vaultProxy.stableCollateralTotal()) - netTotal;
            uint256 stableCollateralBalance;

            if (totalAfterSettlement < 0) {
                stableCollateralBalance = 0;
            } else {
                stableCollateralBalance = uint256(totalAfterSettlement);
            }

            collateralPerShare = (stableCollateralBalance * (10 ** stableModProxy.decimals())) / totalSupply;
        } else {
            // no shares have been minted yet
            collateralPerShare = 1e18;
        }
    }

    function _oraclePrice() private view returns (uint256 price) {
        (price, ) = oracleModProxy.getPrice();
    }
}
