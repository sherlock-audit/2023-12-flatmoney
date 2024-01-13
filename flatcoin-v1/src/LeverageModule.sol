// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {ERC721LockableEnumerableUpgradeable} from "./misc/ERC721LockableEnumerableUpgradeable.sol";
import {DecimalMath} from "./libraries/DecimalMath.sol";
import {PerpMath} from "./libraries/PerpMath.sol";
import {FlatcoinErrors} from "./libraries/FlatcoinErrors.sol";
import {FlatcoinStructs} from "./libraries/FlatcoinStructs.sol";
import {FlatcoinModuleKeys} from "./libraries/FlatcoinModuleKeys.sol";
import {FlatcoinEvents} from "./libraries/FlatcoinEvents.sol";
import {ModuleUpgradeable} from "./abstracts/ModuleUpgradeable.sol";

import {IFlatcoinVault} from "./interfaces/IFlatcoinVault.sol";
import {ILeverageModule} from "./interfaces/ILeverageModule.sol";
import {ILiquidationModule} from "./interfaces/ILiquidationModule.sol";
import {IOracleModule} from "./interfaces/IOracleModule.sol";
import {IPointsModule} from "./interfaces/IPointsModule.sol";
import {ILimitOrder} from "./interfaces/ILimitOrder.sol";

// TODO: Implement a function to split an ERC721 position into 2 positions.
// This would make for easier third party integrations like dHedge v2 vaults for withdrawal
contract LeverageModule is ILeverageModule, ModuleUpgradeable, ERC721LockableEnumerableUpgradeable {
    using PerpMath for int256;
    using PerpMath for uint256;
    using DecimalMath for uint256;

    /// @dev ERC721 token ID increment on mint
    uint256 public tokenIdNext;

    /// @notice Leverage trading fee. Charged for opening, adjusting or closing a position.
    /// @dev 1e18 = 100%
    uint256 public levTradingFee; // Fee for leverage position open/close. 1e18 = 100%

    /// @notice Leverage position criteria limits
    /// @notice A minimum margin limit adds a cost to create a position and ensures it can be liquidated at high leverage
    uint256 public marginMin;

    /// @notice Minimum leverage limit ensures that the position is valuable and adds long open interest
    uint256 public leverageMin;

    /// @notice Maximum leverage limit ensures that the position is safely liquidatable by keepers
    uint256 public leverageMax;

    /// @dev To prevent the implementation contract from being used, we invoke the _disableInitializers
    /// function in the constructor to automatically lock it when it is deployed.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Function to initialize this contract.
    function initialize(
        IFlatcoinVault _vault,
        uint256 _levTradingFee,
        uint256 _marginMin,
        uint256 _leverageMin,
        uint256 _leverageMax
    ) external initializer {
        __Module_init(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY, _vault);
        __ERC721_init("Leveraged Position V1", "LEV");

        setLevTradingFee(_levTradingFee);
        setLeverageCriteria(_marginMin, _leverageMin, _leverageMax);
    }

    /////////////////////////////////////////////
    //         Public Write Functions          //
    /////////////////////////////////////////////

    /// @notice User delayed leverage order open. Mints ERC721 token receipt.
    /// @dev Uses the Pyth network price to execute
    /// @param account The user account which has a pending open leverage order
    function executeOpen(
        address account,
        address keeper,
        FlatcoinStructs.Order calldata order
    ) external whenNotPaused onlyAuthorizedModule returns (uint256 newTokenId) {
        // Make sure the oracle price is after the order executability time
        uint32 maxAge = _getMaxAge(order.executableAtTime);
        FlatcoinStructs.AnnouncedLeverageOpen memory announcedOpen = abi.decode(
            order.orderData,
            (FlatcoinStructs.AnnouncedLeverageOpen)
        );

        // check that buy price doesn't exceed requested price
        (uint256 entryPrice, ) = IOracleModule(vault.moduleAddress(FlatcoinModuleKeys._ORACLE_MODULE_KEY)).getPrice({
            maxAge: maxAge
        });

        vault.checkSkewMax({additionalSkew: announcedOpen.additionalSize});

        if (entryPrice > announcedOpen.maxFillPrice)
            revert FlatcoinErrors.HighSlippage(entryPrice, announcedOpen.maxFillPrice);

        // NOTE: We are assuming here that the user doesn't have any open positions.
        // If they are looking to add to an existing position, they should use the `modifyPosition` function.
        // DISCUSS: Consider adding a `modifyPosition` function to allow users to add to existing positions.
        //          Can we could do away with this function and just use `modifyPosition` instead?

        {
            // Check that the total margin deposited by the long traders is not -ve.
            // To get this amount, we will have to account for the PnL and funding fees accrued.
            // If -ve, the liquidations are not working and we need to investigate.
            // DISCUSS: Is this check necessary? If yes, get total PnL and funding fees accrued and
            //          compare that with the total margin deposited.
            //          Even if we decide not to keep this check, we will have to consider this invariant
            //          when we implement the liquidation mechanism and while testing.
            // assert((int256(globalPositions.marginDepositedTotal) + globalMarginDelta) >= 0);

            // Adjust the funding fees accrued by modifying `marginDepositedTotal` and `stableCollateralTotal`.
            // If `globalMarginDelta` is positive, subtract the same from the `stableCollateralTotal`.
            // Else add to the `stableCollateralTotal`.
            // vault.stableModule().adjustStableCollateralTotal(globalMarginDelta);

            // Update the global position data.
            // The margin change is equal to funding fees accrued to longs and the margin deposited by the trader.
            vault.updateGlobalPositionData({
                price: entryPrice,
                marginDelta: int256(announcedOpen.margin),
                additionalSizeDelta: int256(announcedOpen.additionalSize)
            });

            newTokenId = _mint(account);

            vault.setPosition(
                FlatcoinStructs.Position({
                    entryPrice: entryPrice,
                    marginDeposited: announcedOpen.margin,
                    additionalSize: announcedOpen.additionalSize,
                    entryCumulativeFunding: vault.cumulativeFundingRate()
                }),
                newTokenId
            );
        }
        // Check that the new position isn't immediately liquidatable.
        if (
            ILiquidationModule(vault.moduleAddress(FlatcoinModuleKeys._LIQUIDATION_MODULE_KEY)).canLiquidate(newTokenId)
        ) revert FlatcoinErrors.PositionCreatesBadDebt();

        // Mint points
        IPointsModule pointsModule = IPointsModule(vault.moduleAddress(FlatcoinModuleKeys._POINTS_MODULE_KEY));
        pointsModule.mintLeverageOpen(account, announcedOpen.additionalSize);

        // Settle the collateral
        // TODO: in the future, a portion of the trading fee could go to the DAO
        vault.updateStableCollateralTotal(int256(announcedOpen.tradeFee)); // pay the trade fee to stable LPs

        vault.sendCollateral({to: keeper, amount: order.keeperFee}); // pay the keeper their fee

        emit FlatcoinEvents.LeverageOpen(account, newTokenId);
    }

    function executeAdjust(
        address account,
        address keeper,
        FlatcoinStructs.Order calldata order
    ) external whenNotPaused onlyAuthorizedModule {
        FlatcoinStructs.AnnouncedLeverageAdjust memory announcedAdjust = abi.decode(
            order.orderData,
            (FlatcoinStructs.AnnouncedLeverageAdjust)
        );
        uint32 maxAge = _getMaxAge(order.executableAtTime);
        IOracleModule oracleModule = IOracleModule(vault.moduleAddress(FlatcoinModuleKeys._ORACLE_MODULE_KEY));
        uint256 adjustPrice;
        bool sizeIncrease = announcedAdjust.additionalSizeAdjustment >= 0;

        if (sizeIncrease) vault.checkSkewMax(uint256(announcedAdjust.additionalSizeAdjustment));

        if (sizeIncrease) {
            (adjustPrice, ) = oracleModule.getPrice({maxAge: maxAge});
            if (adjustPrice > announcedAdjust.fillPrice)
                revert FlatcoinErrors.HighSlippage(adjustPrice, announcedAdjust.fillPrice);
        } else {
            (adjustPrice, ) = oracleModule.getPrice({maxAge: maxAge});
            if (adjustPrice < announcedAdjust.fillPrice)
                revert FlatcoinErrors.HighSlippage(adjustPrice, announcedAdjust.fillPrice);
        }

        FlatcoinStructs.Position memory position = vault.getPosition(announcedAdjust.tokenId);

        vault.updateGlobalPositionData({
            price: adjustPrice,
            marginDelta: announcedAdjust.marginAdjustment > 0
                ? announcedAdjust.marginAdjustment
                : announcedAdjust.marginAdjustment - int256(announcedAdjust.totalFee), // fees come out from the margin
            additionalSizeDelta: announcedAdjust.additionalSizeAdjustment
        });

        int256 newEntryPrice = (int256(position.entryPrice * position.additionalSize) +
            int256(adjustPrice) *
            announcedAdjust.additionalSizeAdjustment) / int256(announcedAdjust.newAdditionalSize);

        int256 newEntryCumulativeFunding = (position.entryCumulativeFunding *
            int256(position.additionalSize) +
            vault.cumulativeFundingRate() *
            announcedAdjust.additionalSizeAdjustment) / (int256(announcedAdjust.newAdditionalSize));

        vault.setPosition(
            FlatcoinStructs.Position({
                entryPrice: uint256(newEntryPrice),
                marginDeposited: announcedAdjust.newMargin,
                additionalSize: announcedAdjust.newAdditionalSize,
                entryCumulativeFunding: newEntryCumulativeFunding
            }),
            announcedAdjust.tokenId
        );

        // Check if adjusted position didn't become liquidatable
        if (
            ILiquidationModule(vault.moduleAddress(FlatcoinModuleKeys._LIQUIDATION_MODULE_KEY)).canLiquidate(
                announcedAdjust.tokenId
            )
        ) revert FlatcoinErrors.PositionCreatesBadDebt();

        // Unlock the position token to allow for transfers.
        _unlock(announcedAdjust.tokenId);

        // Mint points
        if (announcedAdjust.additionalSizeAdjustment > 0) {
            address positionOwner = ownerOf(announcedAdjust.tokenId);
            IPointsModule pointsModule = IPointsModule(vault.moduleAddress(FlatcoinModuleKeys._POINTS_MODULE_KEY));

            pointsModule.mintLeverageOpen(positionOwner, uint256(announcedAdjust.additionalSizeAdjustment));
        }

        if (announcedAdjust.tradeFee > 0) vault.updateStableCollateralTotal(int256(announcedAdjust.tradeFee));

        // Sending keeper fee from order contract to the executor
        vault.sendCollateral({to: keeper, amount: order.keeperFee});
        if (announcedAdjust.marginAdjustment < 0) {
            // We send the user that much margin they requested during announceLeverageAdjust(),
            // however their remaining margin is reduced by the fees. It is accounted in announceLeverageAdjust()
            uint256 marginToWithdraw = uint256(announcedAdjust.marginAdjustment * -1);
            // Withdrawing margin from the vault and sending it to the user
            vault.sendCollateral({to: account, amount: marginToWithdraw});
        }

        emit FlatcoinEvents.LeverageAdjust(announcedAdjust.tokenId);
    }

    function executeClose(
        address account,
        address keeper,
        FlatcoinStructs.Order calldata order
    ) external whenNotPaused onlyAuthorizedModule returns (int256 settledMargin) {
        FlatcoinStructs.AnnouncedLeverageClose memory announcedClose = abi.decode(
            order.orderData,
            (FlatcoinStructs.AnnouncedLeverageClose)
        );
        FlatcoinStructs.Position memory position = vault.getPosition(announcedClose.tokenId);

        // Make sure the oracle price is after the order executability time
        uint32 maxAge = _getMaxAge(order.executableAtTime);

        // check that sell price doesn't exceed requested price
        (uint256 exitPrice, ) = IOracleModule(vault.moduleAddress(FlatcoinModuleKeys._ORACLE_MODULE_KEY)).getPrice({
            maxAge: maxAge
        });
        if (exitPrice < announcedClose.minFillPrice)
            revert FlatcoinErrors.HighSlippage(exitPrice, announcedClose.minFillPrice);

        uint256 totalFee;

        {
            FlatcoinStructs.PositionSummary memory positionSummary = PerpMath._getPositionSummary(
                position,
                vault.cumulativeFundingRate(),
                exitPrice
            );
            // Check that the total margin deposited by the long traders is not -ve.
            // To get this amount, we will have to account for the PnL and funding fees accrued.
            // If -ve, the liquidations are not working and we need to investigate.
            // DISCUSS: Is this check necessary? If yes, get total PnL and funding fees accrued and
            //          compare that with the total margin deposited.
            //          Even if we decide not to keep this check, we will have to consider this invariant
            //          when we implement the liquidation mechanism and while testing.
            // assert((int256(globalPositions.marginDepositedTotal) + globalMarginDelta) >= 0);
            settledMargin = positionSummary.marginAfterSettlement;
            totalFee = announcedClose.tradeFee + order.keeperFee;

            if (settledMargin <= 0) revert FlatcoinErrors.ValueNotPositive("settledMargin");

            // Make sure there is enough margin in the position to pay the keeper fee
            if (settledMargin < int256(totalFee)) revert FlatcoinErrors.NotEnoughMarginForFees(settledMargin, totalFee);

            // Adjust the stable collateral total to account for user's profit and funding accrued.
            // vault.stableModule().adjustStableCollateralTotal(globalMarginDelta + positionSummary.profitLoss);
            vault.updateStableCollateralTotal(-positionSummary.profitLoss);

            // Update the global position data.
            // Note that we are only accounting for `globalMarginDelta`, `marginDeposited` and `userAccruedFunding`.
            // and not the PnL of the user when altering `marginDepositedTotal`.
            // This is because the PnL is already accounted for in the `stableCollateralTotal`.
            // So when the PnL is +ve (the trader made profits), the trader takes the profit along with the margin deposited.
            // When the PnL is -ve, the trader loses a portion of the margin deposited to the LPs and the rest is again taken along.
            // In neither case, the PnL is added/subtracted to/from the `marginDepositedTotal`.
            // Now we are subtracting `userAccruedFunding` in the below function call because:
            //      `globalMarginDelta` = `userAccruedFunding` + Funding accrued by the rest of the long traders.
            // And this accrued funding is being taken away from the system (if +ve) or given to LPs (if -ve).
            // When the `userAccruedFunding` is +ve, the user takes away the funding fees earned.
            // When it's negative, the user pays the funding fees to the LPs and their margin is reduced.
            // So the `marginDepositedTotal` is added with `userAccruedFunding` in the below function call as the user has paid for their share
            // of funding fees.
            vault.updateGlobalPositionData({
                price: position.entryPrice,
                marginDelta: -(int256(position.marginDeposited) + positionSummary.accruedFunding),
                additionalSizeDelta: -int256(position.additionalSize) // Since position is being closed, additionalSizeDelta should be negative.
            });

            // Delete position storage
            vault.deletePosition(announcedClose.tokenId);
        }

        // Cancel any existing limit order on the position
        ILimitOrder(vault.moduleAddress(FlatcoinModuleKeys._LIMIT_ORDER_KEY)).cancelExistingLimitOrder(
            announcedClose.tokenId
        );

        // A position NFT has to be unlocked before burning otherwise, the transfer to address(0) will fail.
        _unlock(announcedClose.tokenId);
        _burn(announcedClose.tokenId);

        vault.updateStableCollateralTotal(int256(announcedClose.tradeFee)); // pay the trade fee to stable LPs

        vault.sendCollateral({to: keeper, amount: order.keeperFee}); // pay the keeper their fee
        vault.sendCollateral({to: account, amount: uint256(settledMargin) - totalFee}); // transfer remaining amount to the trader

        emit FlatcoinEvents.LeverageClose(announcedClose.tokenId);
    }

    /// @notice Burns the ERC721 token representing the leverage position.
    /// @param tokenId The ERC721 token ID of the leverage position.
    function burn(uint256 tokenId) external onlyAuthorizedModule {
        _burn(tokenId);
    }

    /// @notice Locks the ERC721 token representing the leverage position.
    /// @param tokenId The ERC721 token ID of the leverage position.
    function lock(uint256 tokenId) public onlyAuthorizedModule {
        _lock(tokenId);
    }

    /// @notice Unlocks the ERC721 token representing the leverage position.
    /// @param tokenId The ERC721 token ID of the leverage position.
    function unlock(uint256 tokenId) public onlyAuthorizedModule {
        _unlock(tokenId);
    }

    // TODO: For v1.2 liquidation integration
    /// @notice Liquidates a user position that can be liquidated
    /// @dev Keeper takes a fee from the trader's margin to cover gas costs
    // function liquidatePosition(uint256 tokenId) external returns (bool success) {}

    /////////////////////////////////////////////
    //             View Functions              //
    /////////////////////////////////////////////

    // TODO: For v1.2 liquidation integration
    /// @notice Check whether
    /// @dev Keeper takes a fee from the trader's margin to cover gas costs
    // function canLiquidatePosition(uint256 tokenId) public view returns (bool canLiquidate) {}

    /// @notice Current total size of leverage across all trades.
    /// @dev Adjusted for profit and loss
    function currentSizeTotal() public view returns (int256 _currentSizeTotal) {
        FlatcoinStructs.MarketSummary memory marketSummary = getMarketSummary();

        // DISCUSS: Can _currentSizeTotal be negative?
        _currentSizeTotal = int256(vault.getGlobalPositions().sizeOpenedTotal) + marketSummary.profitLossTotalByLongs;
    }

    function isLocked(uint256 tokenId) public view override returns (bool lockStatus) {
        lockStatus = _isLocked[tokenId];
    }

    function getPositionSummary(
        uint256 tokenId
    ) public view returns (FlatcoinStructs.PositionSummary memory positionSummary) {
        FlatcoinStructs.Position memory position = vault.getPosition(tokenId);
        FlatcoinStructs.VaultSummary memory vaultSummary = vault.getVaultSummary();

        // DISCUSS: Pass maxAge to getPrice?
        (uint256 currentPrice, ) = IOracleModule(vault.moduleAddress(FlatcoinModuleKeys._ORACLE_MODULE_KEY)).getPrice();

        // Get the nextFundingEntry for the market.
        int256 nextFundingEntry = PerpMath._nextFundingEntry(
            vaultSummary,
            vault.maxFundingVelocity(),
            vault.maxVelocitySkew()
        );

        return PerpMath._getPositionSummary(position, nextFundingEntry, currentPrice);
    }

    function getMarketSummary() public view returns (FlatcoinStructs.MarketSummary memory marketSummary) {
        FlatcoinStructs.VaultSummary memory vaultSummary = vault.getVaultSummary();

        // DISCUSS: Pass maxAge to getPrice?
        (uint256 currentPrice, ) = IOracleModule(vault.moduleAddress(FlatcoinModuleKeys._ORACLE_MODULE_KEY)).getPrice();

        return
            PerpMath._getMarketSummaryLongs(
                vaultSummary,
                vault.maxFundingVelocity(),
                vault.maxVelocitySkew(),
                currentPrice
            );
    }

    function fundingAdjustedLongPnLTotal() public view returns (int256 _fundingAdjustedPnL) {
        return fundingAdjustedLongPnLTotal({maxAge: type(uint32).max});
    }

    function fundingAdjustedLongPnLTotal(uint32 maxAge) public view returns (int256 _fundingAdjustedPnL) {
        (uint256 currentPrice, ) = IOracleModule(vault.moduleAddress(FlatcoinModuleKeys._ORACLE_MODULE_KEY)).getPrice({
            maxAge: maxAge
        });
        FlatcoinStructs.VaultSummary memory vaultSummary = vault.getVaultSummary();
        FlatcoinStructs.MarketSummary memory marketSummary = PerpMath._getMarketSummaryLongs(
            vaultSummary,
            vault.maxFundingVelocity(),
            vault.maxVelocitySkew(),
            currentPrice
        );

        return marketSummary.profitLossTotalByLongs + marketSummary.accruedFundingTotalByLongs;
    }

    /// @notice Asserts that the position to be opened meets margin and size criteria
    function checkLeverageCriteria(uint256 margin, uint256 size) public view {
        uint256 leverage = ((margin + size) * 1e18) / margin;
        if (leverage < leverageMin) revert FlatcoinErrors.LeverageTooLow(leverageMin, leverage);
        if (leverage > leverageMax) revert FlatcoinErrors.LeverageTooHigh(leverageMax, leverage);
        if (margin < marginMin) revert FlatcoinErrors.MarginTooSmall(marginMin, margin);
    }

    function getTradeFee(uint256 size) external view returns (uint256 tradeFee) {
        tradeFee = levTradingFee._multiplyDecimal(size);
    }

    /////////////////////////////////////////////
    //            Internal Functions           //
    /////////////////////////////////////////////

    /// @notice Handles incrementing the tokenIdNext and minting the nft
    /// @param to the minter's address
    function _mint(address to) internal returns (uint256 tokenId) {
        tokenId = tokenIdNext;
        _safeMint(to, tokenIdNext);
        tokenIdNext += 1;
    }

    function _getMaxAge(uint64 executableAtTime) internal view returns (uint32 maxAge) {
        maxAge = uint32(block.timestamp - executableAtTime);
    }

    /////////////////////////////////////////////
    //             Owner Functions             //
    /////////////////////////////////////////////

    /// @notice Setter for the leverage open/close fee
    /// @dev Fees can be set to 0 if needed
    function setLevTradingFee(uint256 _levTradingFee) public onlyOwner {
        // set fee cap to max 1%
        if (_levTradingFee > 0.01e18) revert FlatcoinErrors.InvalidFee(_levTradingFee);

        levTradingFee = _levTradingFee;
    }

    /// @notice Setter for the leverage position criteria limits
    function setLeverageCriteria(uint256 _marginMin, uint256 _leverageMin, uint256 _leverageMax) public onlyOwner {
        if (_leverageMax <= _leverageMin) revert FlatcoinErrors.InvalidLeverageCriteria();

        marginMin = _marginMin;
        leverageMin = _leverageMin;
        leverageMax = _leverageMax;
    }
}
