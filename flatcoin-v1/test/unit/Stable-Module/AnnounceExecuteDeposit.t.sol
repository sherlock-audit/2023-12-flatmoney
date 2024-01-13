// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {OrderHelpers} from "../../helpers/OrderHelpers.sol";

import "forge-std/console2.sol";

contract AnnounceExecuteDepositTest is Setup, OrderHelpers {
    function test_deposits() public {
        // First deposit mint doesn't use offchain oracle price
        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 1200e8,
            keeperFeeAmount: 0
        });

        // Uses offchain oracle price on deposit to mint deposit tokens
        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 100e18,
            oraclePrice: 1800e8, // increase oracle price
            keeperFeeAmount: 0
        });

        announceAndExecuteDeposit({
            traderAccount: alice,
            keeperAccount: keeper,
            depositAmount: 50e18,
            oraclePrice: 1000e8, // decrease oracle price
            keeperFeeAmount: 0
        });
    }
}
