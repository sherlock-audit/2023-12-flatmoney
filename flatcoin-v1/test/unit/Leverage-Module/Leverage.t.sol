// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {OrderHelpers} from "../../helpers/OrderHelpers.sol";
import {ExpectRevert} from "../../helpers/ExpectRevert.sol";

import {FlatcoinErrors} from "../../../src/libraries/FlatcoinErrors.sol";

import "forge-std/console2.sol";

contract LeverageTest is Setup, OrderHelpers, ExpectRevert {
    function test_leverage_open() public {
        _leverageOpen();
        _leverageOpen();
        _leverageOpen();
    }

    function test_leverage_close() public {
        _leverageClose();
        _leverageClose();
        _leverageClose();
    }

    function test_revert_leverage_open_but_position_creates_bad_debt() public {
        setWethPrice(1000e8);

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 1000e8,
            keeperFeeAmount: 0
        });

        vm.startPrank(admin);

        // Effectively remove the max leverage limit so that a position is immediately liquidatable.
        // Immediately liquidatable due to liquidation buffer provided being less than required
        // for the position size.
        leverageModProxy.setLeverageCriteria({
            _marginMin: 0.05e18,
            _leverageMin: 1.5e18,
            _leverageMax: type(uint256).max
        });

        // Announce a position which is immediately liquidatable. This should revert.
        _expectRevertWithCustomError({
            target: address(this),
            callData: abi.encodeWithSelector(OrderHelpers.announceOpenLeverage.selector, alice, 0.05e18, 120e18, 0),
            expectedErrorSignature: "PositionCreatesBadDebt()",
            ignoreErrorArguments: true
        });
    }

    // TODO: Consider moving helper functions to a separate contract

    function _leverageOpen() internal {
        // First deposit mint doesn't use offchain oracle price
        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });

        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 100e18,
            additionalSize: 100e18,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });
    }

    function _leverageClose() internal {
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

        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 100e18,
            additionalSize: 100e18,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });

        announceAndExecuteLeverageClose({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: 2000e8,
            keeperFeeAmount: 0
        });
    }
}
