// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {IPyth} from "pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "pyth-sdk-solidity/PythStructs.sol";

import {Setup} from "../../helpers/Setup.sol";
import {DelayedOrder} from "../../../src/DelayedOrder.sol";
import {MockGasPriceOracleConfig} from "../mocks/MockGasPriceOracleConfig.sol";
import {KeeperFee} from "../../../src/misc/KeeperFee.sol";
import {FlatcoinModuleKeys} from "../../../src/libraries/FlatcoinModuleKeys.sol";
import {FlatcoinStructs} from "../../../src/libraries/FlatcoinStructs.sol";

contract KeeperFeeTest is Setup {
    function test_keeper_fee() public {
        vm.startPrank(admin);
        // This tests the actual KeeperFee.sol contract (doesn't use the MockKeeperFee).
        // It uses a MockGasPriceOracleConfig contract for gas price estimation settings.

        MockGasPriceOracleConfig mockGasPriceOracle = new MockGasPriceOracleConfig();

        KeeperFee keeperFeeContract = new KeeperFee({
            owner: admin,
            ethOracle: address(wethChainlinkAggregatorV3),
            oracleModule: address(oracleModProxy),
            assetToPayWith: address(WETH),
            profitMarginUSD: 1e18,
            profitMarginPercent: 0.3e18,
            keeperFeeUpperBound: 30e18, // In USD
            keeperFeeLowerBound: 2e18, // In USD
            gasUnitsL1: 30_000,
            gasUnitsL2: 1_200_000
        });

        uint256 wethPrice = 2000e8;

        setWethPrice(wethPrice);

        vaultProxy.addAuthorizedModule(
            FlatcoinStructs.AuthorizedModule({
                moduleKey: FlatcoinModuleKeys._KEEPER_FEE_MODULE_KEY,
                moduleAddress: address(keeperFeeContract)
            })
        );

        keeperFeeContract.setGasPriceOracle(address(mockGasPriceOracle));

        uint256 keeperFee = keeperFeeContract.getKeeperFee();

        (
            address gasPriceOracle,
            uint256 profitMarginUSD,
            uint256 profitMarginPercent,
            uint256 keeperFeeUpperBound,
            uint256 keeperFeeLowerBound,
            uint256 gasUnitsL1,
            uint256 gasUnitsL2
        ) = keeperFeeContract.getConfig();

        // Expected keeper fee using specific MockGasPriceOracleConfig settings.
        // NOTE: The fee is around $1.62 but as this is lesser than the lower bound of $2, the lower bound is used.
        //       Also this fee is returned in the collateral asset (WETH) so the hardcoded value is in WETH.
        assertEq(keeperFee, (2e18 * 1e8) / wethPrice, "Invalid keeper fee value");

        assertGe(keeperFee, (keeperFeeLowerBound * 1e8) / wethPrice, "Keeper fee hit lower bound");
        assertLe(keeperFee, (keeperFeeUpperBound * 1e8) / wethPrice, "Keeper fee hit upper bound");
        assertEq(gasPriceOracle, address(mockGasPriceOracle), "Invalid gasPriceOracle");
        assertEq(profitMarginUSD, 1e18, "Invalid profitMarginUSD");
        assertEq(profitMarginUSD, 1e18, "Invalid profitMarginUSD");
        assertEq(profitMarginPercent, 0.3e18, "Invalid profitMarginPercent");
        assertEq(keeperFeeUpperBound, 30e18, "Invalid keeperFeeUpperBound");
        assertEq(keeperFeeLowerBound, 2e18, "Invalid keeperFeeLowerBound");
        assertEq(gasUnitsL1, 30_000, "Invalid gasUnitsL1");
        assertEq(gasUnitsL2, 1_200_000, "Invalid gasUnitsL2");
    }
}
