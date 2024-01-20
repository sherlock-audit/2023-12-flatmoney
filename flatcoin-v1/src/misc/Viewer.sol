// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {DecimalMath} from "../libraries/DecimalMath.sol";
import {IFlatcoinVault} from "../interfaces/IFlatcoinVault.sol";
import {ILeverageModule} from "../interfaces/ILeverageModule.sol";
import {IStableModule} from "../interfaces/IStableModule.sol";
import {IOracleModule} from "../interfaces/IOracleModule.sol";
import {ILiquidationModule} from "../interfaces/ILiquidationModule.sol";
import {FlatcoinStructs} from "../libraries/FlatcoinStructs.sol";
import {FlatcoinModuleKeys} from "../libraries/FlatcoinModuleKeys.sol";

/// @title Viewer contract for Flatcoin
/// @notice Contains functions to view details about Flatcoin and related data.
/// @dev Should only be used by 3rd party integrations and frontends.
contract Viewer {
    using SignedMath for int256;
    using DecimalMath for int256;

    IFlatcoinVault public vault;

    constructor(IFlatcoinVault _vault) {
        vault = _vault;
    }

    /////////////////////////////////////////////
    //             View Functions              //
    /////////////////////////////////////////////

    function getAccountLeveragePositionData(
        address account
    ) external view returns (FlatcoinStructs.LeveragePositionData[] memory positionData) {
        ILeverageModule leverageModule = ILeverageModule(vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY));

        uint256 balance = leverageModule.balanceOf(account);
        positionData = new FlatcoinStructs.LeveragePositionData[](balance);

        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = leverageModule.tokenOfOwnerByIndex(account, i);
            positionData[i] = getPositionData(tokenId);
        }
    }

    /// @notice Returns leverage position data for a range of position IDs
    /// @dev For a closed position, the token is burned and position data will be 0
    function getPositionData(
        uint256 tokenIdFrom,
        uint256 tokenIdTo
    ) external view returns (FlatcoinStructs.LeveragePositionData[] memory positionData) {
        uint256 length = tokenIdTo - tokenIdFrom + 1;
        positionData = new FlatcoinStructs.LeveragePositionData[](length);

        for (uint256 i = 0; i < length; i++) {
            positionData[i] = getPositionData(i + tokenIdFrom);
        }
    }

    /// @notice Returns leverage position data for a specific position ID
    /// @dev For a closed position, the token is burned and position data will be 0
    function getPositionData(
        uint256 tokenId
    ) public view returns (FlatcoinStructs.LeveragePositionData memory positionData) {
        ILeverageModule leverageModule = ILeverageModule(vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY));
        ILiquidationModule liquidationModule = ILiquidationModule(
            vault.moduleAddress(FlatcoinModuleKeys._LIQUIDATION_MODULE_KEY)
        );

        FlatcoinStructs.Position memory position = vault.getPosition(tokenId);
        FlatcoinStructs.PositionSummary memory positionSummary = leverageModule.getPositionSummary(tokenId);
        uint256 liquidationPrice = liquidationModule.liquidationPrice(tokenId);

        positionData = FlatcoinStructs.LeveragePositionData({
            tokenId: tokenId,
            lastPrice: position.lastPrice,
            marginDeposited: position.marginDeposited,
            additionalSize: position.additionalSize,
            entryCumulativeFunding: position.entryCumulativeFunding,
            profitLoss: positionSummary.profitLoss,
            accruedFunding: positionSummary.accruedFunding,
            marginAfterSettlement: positionSummary.marginAfterSettlement,
            liquidationPrice: liquidationPrice
        });
    }

    function getFlatcoinTVL() external view returns (uint256 tvl) {
        IOracleModule oracleModule = IOracleModule(vault.moduleAddress(FlatcoinModuleKeys._ORACLE_MODULE_KEY));
        IStableModule stableModule = IStableModule(vault.moduleAddress(FlatcoinModuleKeys._STABLE_MODULE_KEY));
        FlatcoinStructs.VaultSummary memory vaultSummary = vault.getVaultSummary();

        (uint256 price, ) = oracleModule.getPrice();
        tvl = (vaultSummary.stableCollateralTotal * price) / (10 ** stableModule.decimals());
    }

    /// @notice Returns the market skew in percentage terms.
    /// @return skewPercent The market skew in percentage terms [-1e18, (1 - skewFractionMax)*1e18].
    /// @dev When the `skewPercent` is -1e18 it means the market is fully skewed towards stable LPs.
    ///      When the `skewPercent` is (1 - skewFractionMax)*1e18 it means the market is skewed max towards leverage LPs.
    ///      When the `skewPercent` is 0 it means the market is either perfectly hedged or there is no stable collateral.
    /// @dev Note that this `skewPercent` is relative to the stable collateral.
    ///      So it's max value is (1 - skewFractionMax)*1e18. For example, if the `skewFractionMax` is 1.2e18,
    ///      the max value of `skewPercent` is 0.2e18. This means that the market is skewed 20% towards leverage LPs
    ///      relative to the stable collateral.
    function getMarketSkewPercentage() external view returns (int256 skewPercent) {
        FlatcoinStructs.VaultSummary memory vaultSummary = vault.getVaultSummary();

        int256 marketSkew = vault.getCurrentSkew();
        uint256 stableCollateralTotal = vaultSummary.stableCollateralTotal;

        // Technically, the market skew is undefined when there are no open positions.
        // Since no leverage position can be opened when there is no stable collateral in the vault,
        // it also means stable collateral == leverage long margin and hence no skew.
        if (stableCollateralTotal == 0) {
            return 0;
        } else {
            return marketSkew._divideDecimal(int256(stableCollateralTotal));
        }
    }

    function getFlatcoinPriceInUSD() external view returns (uint256 priceInUSD) {
        IStableModule stableModule = IStableModule(vault.moduleAddress(FlatcoinModuleKeys._STABLE_MODULE_KEY));
        uint256 tokenPriceInCollateral = stableModule.stableCollateralPerShare();
        (uint256 collateralPriceInUSD, ) = IOracleModule(vault.moduleAddress(FlatcoinModuleKeys._ORACLE_MODULE_KEY))
            .getPrice();

        priceInUSD = (tokenPriceInCollateral * collateralPriceInUSD) / (10 ** stableModule.decimals());
    }
}
