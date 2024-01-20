// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {ExpectRevert} from "../../helpers/ExpectRevert.sol";
import {OrderHelpers} from "../../helpers/OrderHelpers.sol";
import {FlatcoinErrors} from "../../../src/libraries/FlatcoinErrors.sol";

contract DelayedOrderTest is OrderHelpers, ExpectRevert {
    function test_revert_when_module_paused() public {
        bytes32 moduleKey = delayedOrderProxy.MODULE_KEY();

        vm.prank(admin);
        vaultProxy.pauseModule(moduleKey);

        _expectRevertWithCustomError({
            target: address(delayedOrderProxy),
            callData: abi.encodeWithSelector(
                delayedOrderProxy.announceStableDeposit.selector,
                0,
                0,
                mockKeeperFee.getKeeperFee()
            ),
            expectedErrorSignature: "Paused(bytes32)",
            errorData: abi.encodeWithSelector(FlatcoinErrors.Paused.selector, moduleKey)
        });

        _expectRevertWithCustomError({
            target: address(delayedOrderProxy),
            callData: abi.encodeWithSelector(
                delayedOrderProxy.announceStableWithdraw.selector,
                0,
                0,
                mockKeeperFee.getKeeperFee()
            ),
            expectedErrorSignature: "Paused(bytes32)",
            errorData: abi.encodeWithSelector(FlatcoinErrors.Paused.selector, moduleKey)
        });

        _expectRevertWithCustomError({
            target: address(delayedOrderProxy),
            callData: abi.encodeWithSelector(
                delayedOrderProxy.announceLeverageOpen.selector,
                0,
                0,
                0,
                mockKeeperFee.getKeeperFee()
            ),
            expectedErrorSignature: "Paused(bytes32)",
            errorData: abi.encodeWithSelector(FlatcoinErrors.Paused.selector, moduleKey)
        });

        _expectRevertWithCustomError({
            target: address(delayedOrderProxy),
            callData: abi.encodeWithSelector(
                delayedOrderProxy.announceLeverageAdjust.selector,
                0,
                0,
                0,
                0,
                mockKeeperFee.getKeeperFee()
            ),
            expectedErrorSignature: "Paused(bytes32)",
            errorData: abi.encodeWithSelector(FlatcoinErrors.Paused.selector, moduleKey)
        });

        _expectRevertWithCustomError({
            target: address(delayedOrderProxy),
            callData: abi.encodeWithSelector(
                delayedOrderProxy.announceLeverageClose.selector,
                0,
                0,
                mockKeeperFee.getKeeperFee()
            ),
            expectedErrorSignature: "Paused(bytes32)",
            errorData: abi.encodeWithSelector(FlatcoinErrors.Paused.selector, moduleKey)
        });

        bytes[] memory emptyByteArray;

        _expectRevertWithCustomError({
            target: address(delayedOrderProxy),
            callData: abi.encodeWithSelector(
                delayedOrderProxy.executeOrder.selector,
                admin,
                emptyByteArray,
                mockKeeperFee.getKeeperFee()
            ),
            expectedErrorSignature: "Paused(bytes32)",
            errorData: abi.encodeWithSelector(FlatcoinErrors.Paused.selector, moduleKey)
        });
    }

    function test_revert_announce_deposit_when_deposit_amount_too_small() public {
        uint256 depositAmount = 100;
        uint256 quotedAmount = stableModProxy.stableDepositQuote(depositAmount);

        _expectRevertWithCustomError({
            target: address(delayedOrderProxy),
            callData: abi.encodeWithSelector(
                delayedOrderProxy.announceStableDeposit.selector,
                depositAmount,
                quotedAmount,
                mockKeeperFee.getKeeperFee()
            ),
            expectedErrorSignature: "AmountTooSmall(uint256,uint256)",
            errorData: abi.encodeWithSelector(
                FlatcoinErrors.AmountTooSmall.selector,
                depositAmount,
                delayedOrderProxy.MIN_DEPOSIT()
            )
        });
    }

    function test_revert_announce_deposit_when_slippage_is_high() public {
        uint256 depositAmount = 0.1e18;
        uint256 quotedAmount = stableModProxy.stableDepositQuote(depositAmount);
        uint256 minAmountOut = 1e18;

        _expectRevertWithCustomError({
            target: address(delayedOrderProxy),
            callData: abi.encodeWithSelector(
                delayedOrderProxy.announceStableDeposit.selector,
                depositAmount,
                minAmountOut,
                mockKeeperFee.getKeeperFee()
            ),
            expectedErrorSignature: "HighSlippage(uint256,uint256)",
            errorData: abi.encodeWithSelector(FlatcoinErrors.HighSlippage.selector, quotedAmount, minAmountOut)
        });
    }

    function test_revert_announce_deposit_when_keeper_fee_too_small() public {
        uint256 depositAmount = 1e18;
        uint256 quotedAmount = stableModProxy.stableDepositQuote(depositAmount);
        uint256 keeperFee = 0;

        _expectRevertWithCustomError({
            target: address(delayedOrderProxy),
            callData: abi.encodeWithSelector(
                delayedOrderProxy.announceStableDeposit.selector,
                depositAmount,
                quotedAmount,
                keeperFee
            ),
            expectedErrorSignature: "InvalidFee(uint256)",
            errorData: abi.encodeWithSelector(FlatcoinErrors.InvalidFee.selector, keeperFee)
        });
    }

    function test_revert_announce_deposit_when_deposit_amount_not_approved() public {
        uint256 depositAmount = 1e18;
        uint256 quotedAmount = stableModProxy.stableDepositQuote(depositAmount);
        uint256 keeperFee = mockKeeperFee.getKeeperFee();

        _expectRevertWith({
            target: address(delayedOrderProxy),
            callData: abi.encodeWithSelector(
                delayedOrderProxy.announceStableDeposit.selector,
                depositAmount,
                quotedAmount,
                keeperFee
            ),
            revertMessage: "ERC20: insufficient allowance"
        });
    }

    function test_revert_announce_deposit_when_previous_order_has_not_expired() public {
        vm.startPrank(alice);

        uint256 depositAmount = 1e18;
        uint256 quotedAmount = stableModProxy.stableDepositQuote(depositAmount);
        uint256 keeperFee = mockKeeperFee.getKeeperFee();

        WETH.increaseAllowance(address(delayedOrderProxy), (depositAmount + keeperFee) * 2);

        delayedOrderProxy.announceStableDeposit(depositAmount, quotedAmount, keeperFee);

        _expectRevertWithCustomError({
            target: address(delayedOrderProxy),
            callData: abi.encodeWithSelector(
                delayedOrderProxy.announceStableDeposit.selector,
                depositAmount,
                quotedAmount,
                keeperFee
            ),
            expectedErrorSignature: "OrderHasNotExpired()",
            errorData: abi.encodeWithSelector(FlatcoinErrors.OrderHasNotExpired.selector)
        });
    }

    function test_revert_announce_withdraw_when_amount_not_enough() public {
        vm.startPrank(alice);

        uint256 withdrawAmount = 1e18;

        _expectRevertWithCustomError({
            target: address(delayedOrderProxy),
            callData: abi.encodeWithSelector(
                delayedOrderProxy.announceStableWithdraw.selector,
                withdrawAmount,
                0,
                mockKeeperFee.getKeeperFee()
            ),
            expectedErrorSignature: "NotEnoughBalanceForWithdraw(address,uint256,uint256)",
            errorData: abi.encodeWithSelector(
                FlatcoinErrors.NotEnoughBalanceForWithdraw.selector,
                alice,
                0,
                withdrawAmount
            )
        });
    }

    function test_revert_announce_withdraw_when_slippage_is_high() public {
        uint256 depositAmount = 1e18;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: depositAmount,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        vm.startPrank(alice);

        uint256 minAmountOut = 1e18;
        uint256 keeperFee = mockKeeperFee.getKeeperFee();
        uint256 quotedAmount = stableModProxy.stableWithdrawQuote(depositAmount) - keeperFee;

        _expectRevertWithCustomError({
            target: address(delayedOrderProxy),
            callData: abi.encodeWithSelector(
                delayedOrderProxy.announceStableWithdraw.selector,
                depositAmount,
                minAmountOut,
                keeperFee
            ),
            expectedErrorSignature: "HighSlippage(uint256,uint256)",
            errorData: abi.encodeWithSelector(FlatcoinErrors.HighSlippage.selector, quotedAmount, minAmountOut)
        });
    }

    function test_revert_announce_open_when_price_too_low() public {
        uint256 depositAmount = 1e18;
        uint256 currentPrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: depositAmount,
            oraclePrice: currentPrice,
            keeperFeeAmount: 0
        });

        uint256 maxFillPrice = 900e18;

        _expectRevertWithCustomError({
            target: address(delayedOrderProxy),
            callData: abi.encodeWithSelector(
                delayedOrderProxy.announceLeverageOpen.selector,
                depositAmount,
                depositAmount,
                maxFillPrice,
                mockKeeperFee.getKeeperFee()
            ),
            expectedErrorSignature: "MaxFillPriceTooLow(uint256,uint256)",
            errorData: abi.encodeWithSelector(
                FlatcoinErrors.MaxFillPriceTooLow.selector,
                maxFillPrice,
                currentPrice * 1e10
            )
        });
    }

    function test_revert_announce_adjust_when_price_too_low() public {
        uint256 depositAmount = 1e18;
        uint256 currentPrice = 1000e8;

        uint256 tokenId = announceAndExecuteDepositAndLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: depositAmount * 2,
            margin: depositAmount,
            additionalSize: depositAmount,
            oraclePrice: currentPrice,
            keeperFeeAmount: 0
        });

        uint256 fillPrice = 900e18;

        vm.startPrank(alice);

        _expectRevertWithCustomError({
            target: address(delayedOrderProxy),
            callData: abi.encodeWithSelector(
                delayedOrderProxy.announceLeverageAdjust.selector,
                tokenId,
                depositAmount,
                depositAmount,
                fillPrice,
                mockKeeperFee.getKeeperFee()
            ),
            expectedErrorSignature: "MaxFillPriceTooLow(uint256,uint256)",
            errorData: abi.encodeWithSelector(
                FlatcoinErrors.MaxFillPriceTooLow.selector,
                fillPrice,
                currentPrice * 1e10
            )
        });
    }

    function test_revert_announce_adjust_when_price_too_high() public {
        uint256 depositAmount = 1e18;
        uint256 currentPrice = 1000e8;

        uint256 tokenId = announceAndExecuteDepositAndLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: depositAmount * 2,
            margin: depositAmount,
            additionalSize: depositAmount,
            oraclePrice: currentPrice,
            keeperFeeAmount: 0
        });

        uint256 fillPrice = 1100e18;

        vm.startPrank(alice);

        _expectRevertWithCustomError({
            target: address(delayedOrderProxy),
            callData: abi.encodeWithSelector(
                delayedOrderProxy.announceLeverageAdjust.selector,
                tokenId,
                0,
                -0.1e18,
                fillPrice,
                mockKeeperFee.getKeeperFee()
            ),
            expectedErrorSignature: "MinFillPriceTooHigh(uint256,uint256)",
            errorData: abi.encodeWithSelector(
                FlatcoinErrors.MinFillPriceTooHigh.selector,
                fillPrice,
                currentPrice * 1e10
            )
        });
    }

    function test_revert_announce_close_when_caller_not_token_owner() public {
        uint256 depositAmount = 1e18;
        uint256 currentPrice = 1000e8;

        uint256 tokenId = announceAndExecuteDepositAndLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: depositAmount,
            margin: depositAmount,
            additionalSize: depositAmount,
            oraclePrice: currentPrice,
            keeperFeeAmount: 0
        });

        vm.startPrank(bob);

        _expectRevertWithCustomError({
            target: address(delayedOrderProxy),
            callData: abi.encodeWithSelector(
                delayedOrderProxy.announceLeverageClose.selector,
                tokenId,
                currentPrice,
                mockKeeperFee.getKeeperFee()
            ),
            expectedErrorSignature: "NotTokenOwner(uint256,address)",
            errorData: abi.encodeWithSelector(FlatcoinErrors.NotTokenOwner.selector, tokenId, bob)
        });
    }

    function test_revert_announce_close_when_when_price_too_high() public {
        uint256 depositAmount = 1e18;
        uint256 currentPrice = 1000e8;

        uint256 tokenId = announceAndExecuteDepositAndLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: depositAmount * 2,
            margin: depositAmount,
            additionalSize: depositAmount,
            oraclePrice: currentPrice,
            keeperFeeAmount: 0
        });

        uint256 fillPrice = 1100e18;

        vm.startPrank(alice);

        _expectRevertWithCustomError({
            target: address(delayedOrderProxy),
            callData: abi.encodeWithSelector(
                delayedOrderProxy.announceLeverageClose.selector,
                tokenId,
                fillPrice,
                mockKeeperFee.getKeeperFee()
            ),
            expectedErrorSignature: "MinFillPriceTooHigh(uint256,uint256)",
            errorData: abi.encodeWithSelector(
                FlatcoinErrors.MinFillPriceTooHigh.selector,
                fillPrice,
                currentPrice * 1e10
            )
        });
    }

    function test_revert_execute_withdraw_when_time_not_reached() public {
        uint256 oraclePrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 1e18,
            oraclePrice: oraclePrice,
            keeperFeeAmount: 0
        });

        announceStableWithdraw({traderAccount: alice, withdrawAmount: 1e18, keeperFeeAmount: 0});

        vm.startPrank(keeper);

        bytes[] memory priceUpdateData = getPriceUpdateData(oraclePrice);

        _expectRevertWithCustomError({
            target: address(delayedOrderProxy),
            callData: abi.encodeWithSelector(delayedOrderProxy.executeOrder.selector, alice, priceUpdateData),
            expectedErrorSignature: "ExecutableTimeNotReached(uint256)",
            ignoreErrorArguments: true,
            value: 1
        });
    }

    function test_revert_execute_withdraw_when_order_has_expired() public {
        uint256 oraclePrice = 1000e8;

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 1e18,
            oraclePrice: oraclePrice,
            keeperFeeAmount: 0
        });

        announceStableWithdraw({traderAccount: alice, withdrawAmount: 1e18, keeperFeeAmount: 0});

        skip(5 minutes);

        vm.startPrank(keeper);

        bytes[] memory priceUpdateData = getPriceUpdateData(oraclePrice);

        _expectRevertWithCustomError({
            target: address(delayedOrderProxy),
            callData: abi.encodeWithSelector(delayedOrderProxy.executeOrder.selector, alice, priceUpdateData),
            expectedErrorSignature: "OrderHasExpired()",
            ignoreErrorArguments: true,
            value: 1
        });
    }
}
