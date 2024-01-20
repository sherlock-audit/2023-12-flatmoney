// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {ExpectRevert} from "../../helpers/ExpectRevert.sol";
import {OrderHelpers} from "../../helpers/OrderHelpers.sol";
import {FlatcoinStructs} from "src/libraries/FlatcoinStructs.sol";
import {FlatcoinErrors} from "src/libraries/FlatcoinErrors.sol";

import "forge-std/console2.sol";

contract LongSkewMaxTest is Setup, OrderHelpers, ExpectRevert {
    function test_long_skew_max_announce_leverage() public {
        uint256 collateralPrice = 1000e8;
        uint256 stableDeposit = 100e18;
        uint256 margin = 100e18;
        uint256 sizeOk = 120e18; // skew fraction of 1.2
        uint256 sizeNok = 130e18; // skew fraction of 1.3, above configured max

        uint256 keeperFee = mockKeeperFee.getKeeperFee();

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: keeperFee
        });

        uint256 tokenId = announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: margin,
            additionalSize: sizeOk,
            oraclePrice: collateralPrice,
            keeperFeeAmount: keeperFee
        });

        announceAndExecuteLeverageClose({
            tokenId: tokenId,
            traderAccount: alice,
            keeperAccount: keeper,
            oraclePrice: collateralPrice,
            keeperFeeAmount: keeperFee
        });

        // Opening bigger size over the max skew limit should revert
        _expectRevertWithCustomError({
            target: address(this),
            callData: abi.encodeWithSelector(
                OrderHelpers.announceOpenLeverage.selector,
                alice,
                margin,
                sizeNok,
                keeperFee
            ),
            expectedErrorSignature: "MaxSkewReached(uint256)",
            ignoreErrorArguments: true
        });
    }

    function test_long_skew_max_announce_close_lp() public {
        uint256 collateralPrice = 1000e8;
        uint256 stableDeposit = 120e18;
        uint256 margin = 120e18;
        uint256 size = 120e18;

        uint256 keeperFee = mockKeeperFee.getKeeperFee();

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: keeperFee
        });

        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: margin,
            additionalSize: size,
            oraclePrice: collateralPrice,
            keeperFeeAmount: 0
        });

        announceAndExecuteWithdraw({
            traderAccount: alice,
            keeperAccount: keeper,
            withdrawAmount: 20e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: keeperFee
        });

        // Closing any more of the stable LP should push the sytem over the max skew limit and it should revert
        _expectRevertWithCustomError({
            target: address(this),
            callData: abi.encodeWithSelector(OrderHelpers.announceStableWithdraw.selector, alice, 1e18, keeperFee),
            expectedErrorSignature: "MaxSkewReached(uint256)",
            ignoreErrorArguments: true
        });
    }

    function test_long_skew_max_execute_withdraw() public {
        uint256 collateralPrice = 1000e8;
        uint256 stableDeposit = 100e18;
        uint256 margin = 100e18;
        uint256 size = 100e18;

        uint256 keeperFee = mockKeeperFee.getKeeperFee();

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: keeperFee
        });

        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: margin,
            additionalSize: size,
            oraclePrice: collateralPrice,
            keeperFeeAmount: keeperFee
        });

        announceStableWithdraw({traderAccount: alice, withdrawAmount: 15e18, keeperFeeAmount: keeperFee});

        announceAndExecuteLeverageOpen({
            traderAccount: bob,
            keeperAccount: keeper,
            margin: 15e18,
            additionalSize: 15e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: keeperFee
        });

        skip(uint256(vaultProxy.minExecutabilityAge())); // must reach minimum executability time

        // bytes[] memory priceUpdateData = getPriceUpdateData(collateralPrice);

        // Closing more stable LP makes the system reach the max skew limit and should revert
        _expectRevertWithCustomError({
            target: address(this),
            callData: abi.encodeWithSelector(
                OrderHelpers.executeStableWithdraw.selector,
                keeper,
                alice,
                collateralPrice,
                false
            ),
            expectedErrorSignature: "MaxSkewReached(uint256)",
            ignoreErrorArguments: true
        });
    }

    function test_long_skew_max_execute_open() public {
        uint256 collateralPrice = 1000e8;
        uint256 stableDeposit = 100e18;
        uint256 margin = 100e18;
        uint256 size = 100e18;

        uint256 keeperFee = mockKeeperFee.getKeeperFee();

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: stableDeposit,
            oraclePrice: collateralPrice,
            keeperFeeAmount: keeperFee
        });

        announceAndExecuteLeverageOpen({
            traderAccount: alice,
            keeperAccount: keeper,
            margin: margin,
            additionalSize: size,
            oraclePrice: collateralPrice,
            keeperFeeAmount: keeperFee
        });

        announceOpenLeverage({traderAccount: bob, margin: 15e18, additionalSize: 15e18, keeperFeeAmount: keeperFee});

        announceAndExecuteWithdraw({
            traderAccount: alice,
            keeperAccount: keeper,
            withdrawAmount: 15e18,
            oraclePrice: collateralPrice,
            keeperFeeAmount: keeperFee
        });

        skip(uint256(vaultProxy.minExecutabilityAge())); // must reach minimum executability time

        // Opening further leverage makes the system reach the max skew limit and should revert
        _expectRevertWithCustomError({
            target: address(this),
            callData: abi.encodeWithSelector(
                OrderHelpers.executeOpenLeverage.selector,
                keeper,
                bob,
                collateralPrice,
                false
            ),
            expectedErrorSignature: "MaxSkewReached(uint256)",
            ignoreErrorArguments: true
        });
    }
}
