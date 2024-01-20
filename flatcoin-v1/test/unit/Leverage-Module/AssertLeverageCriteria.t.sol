// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {OrderHelpers} from "../../helpers/OrderHelpers.sol";
import {ExpectRevert} from "../../helpers/ExpectRevert.sol";
import {ILeverageModule} from "../../../src/interfaces/ILeverageModule.sol";
import {FlatcoinStructs} from "../../../src/libraries/FlatcoinStructs.sol";
import {FlatcoinErrors} from "src/libraries/FlatcoinErrors.sol";
import "../../../src/interfaces/IChainlinkAggregatorV3.sol";

contract AssertLeverageCriteriaTest is Setup, OrderHelpers, ExpectRevert {
    function test_revert_leverage_assert_criteria() public {
        vm.startPrank(admin);
        leverageModProxy.setLeverageCriteria({_marginMin: 0.01e18, _leverageMin: 1.3e18, _leverageMax: 50e18});

        vm.startPrank(alice);

        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

        assertEq(0.01e18, leverageModProxy.marginMin());
        assertEq(1.3e18, leverageModProxy.leverageMin());
        assertEq(50e18, leverageModProxy.leverageMax());

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        _expectRevertWithCustomError({
            target: address(this),
            callData: abi.encodeWithSelector(
                OrderHelpers.announceOpenLeverage.selector,
                alice,
                0.01e18 - 1,
                0.01e18 - 1,
                0
            ),
            expectedErrorSignature: "MarginTooSmall(uint256,uint256)",
            errorData: abi.encodeWithSelector(FlatcoinErrors.MarginTooSmall.selector, 0.01e18, 0.01e18 - 1)
        });

        _expectRevertWithCustomError({
            target: address(this),
            callData: abi.encodeWithSelector(
                OrderHelpers.announceOpenLeverage.selector,
                alice,
                1e18,
                1.3e18 - 1e18 - 1,
                0
            ),
            expectedErrorSignature: "LeverageTooLow(uint256,uint256)",
            errorData: abi.encodeWithSelector(FlatcoinErrors.LeverageTooLow.selector, 1.3e18, 1.3e18 - 1)
        });

        _expectRevertWithCustomError({
            target: address(this),
            callData: abi.encodeWithSelector(
                OrderHelpers.announceOpenLeverage.selector,
                alice,
                1e18,
                50e18 - 1e18 + 1,
                0
            ),
            expectedErrorSignature: "LeverageTooHigh(uint256,uint256)",
            errorData: abi.encodeWithSelector(FlatcoinErrors.LeverageTooHigh.selector, 50e18, 50e18 + 1)
        });
    }

    function test_leverage_assert_criteria_succeed() public {
        vm.startPrank(admin);
        leverageModProxy.setLeverageCriteria({_marginMin: 0.01e18, _leverageMin: 1.3e18, _leverageMax: 50e18});

        vm.startPrank(alice);

        uint256 stableDeposit = 100e18;
        uint256 collateralPrice = 1000e8;

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
            margin: 0.01e18 + 1,
            additionalSize: 0.01e18 + 1,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 1e18,
            additionalSize: 1.3e18 - 1e18 + 1,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: 1e18,
            additionalSize: 50e18 - 1e18 - 1,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });
    }
}
