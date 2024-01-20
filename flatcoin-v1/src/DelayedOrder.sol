// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";

import {FlatcoinStructs} from "./libraries/FlatcoinStructs.sol";
import {FlatcoinErrors} from "./libraries/FlatcoinErrors.sol";
import {FlatcoinModuleKeys} from "./libraries/FlatcoinModuleKeys.sol";
import {FlatcoinEvents} from "./libraries/FlatcoinEvents.sol";
import {ModuleUpgradeable} from "./abstracts/ModuleUpgradeable.sol";
import {OracleModifiers} from "./abstracts/OracleModifiers.sol";
import {InvariantChecks} from "./misc/InvariantChecks.sol";

import {IDelayedOrder} from "./interfaces/IDelayedOrder.sol";
import {IFlatcoinVault} from "./interfaces/IFlatcoinVault.sol";
import {ILeverageModule} from "./interfaces/ILeverageModule.sol";
import {IStableModule} from "./interfaces/IStableModule.sol";
import {IOracleModule} from "./interfaces/IOracleModule.sol";
import {ILiquidationModule} from "./interfaces/ILiquidationModule.sol";
import {IKeeperFee} from "./interfaces/IKeeperFee.sol";

/// @title DelayedOrder
/// @author dHEDGE
/// @notice Contains functions to announce and execute delayed orders.
contract DelayedOrder is
    IDelayedOrder,
    ModuleUpgradeable,
    ReentrancyGuardUpgradeable,
    InvariantChecks,
    OracleModifiers
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IStableModule;
    using SignedMath for int256;

    /// @notice Minimum deposit amount for stable LP collateral.
    uint256 public constant MIN_DEPOSIT = 1e6;

    /// @dev Mapping containing all the orders in an encoded format.
    mapping(address account => FlatcoinStructs.Order order) private _announcedOrder;

    /// @dev To prevent the implementation contract from being used, we invoke the _disableInitializers
    /// function in the constructor to automatically lock it when it is deployed.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Function to initialize this contract.
    function initialize(IFlatcoinVault _vault) external initializer {
        __Module_init(FlatcoinModuleKeys._DELAYED_ORDER_KEY, _vault);
        __ReentrancyGuard_init();
    }

    /////////////////////////////////////////////
    //         Announcement Functions          //
    /////////////////////////////////////////////

    /// @notice Announces deposit intent for keepers to execute at offchain oracle price.
    /// @dev The deposit amount is taken plus the keeper fee.
    /// @param depositAmount The amount of collateral to deposit.
    /// @param minAmountOut The minimum amount of tokens the user expects to receive back.
    /// @param keeperFee The fee the user is paying for keeper transaction execution (in collateral tokens).
    function announceStableDeposit(
        uint256 depositAmount,
        uint256 minAmountOut,
        uint256 keeperFee
    ) external whenNotPaused {
        uint64 executableAtTime = _prepareAnnouncementOrder(keeperFee);

        vault.checkCollateralCap(depositAmount);

        if (depositAmount < MIN_DEPOSIT)
            revert FlatcoinErrors.AmountTooSmall({amount: depositAmount, minAmount: MIN_DEPOSIT});

        // Check that the requested minAmountOut is feasible
        uint256 quotedAmount = IStableModule(vault.moduleAddress(FlatcoinModuleKeys._STABLE_MODULE_KEY))
            .stableDepositQuote(depositAmount);

        if (quotedAmount < minAmountOut) revert FlatcoinErrors.HighSlippage(quotedAmount, minAmountOut);

        _announcedOrder[msg.sender] = FlatcoinStructs.Order({
            orderType: FlatcoinStructs.OrderType.StableDeposit,
            orderData: abi.encode(
                FlatcoinStructs.AnnouncedStableDeposit({depositAmount: depositAmount, minAmountOut: minAmountOut})
            ),
            keeperFee: keeperFee,
            executableAtTime: executableAtTime
        });

        // Sends collateral to the delayed order contract first before it is settled by keepers and sent to the vault
        vault.collateral().safeTransferFrom(msg.sender, address(this), depositAmount + keeperFee);

        emit FlatcoinEvents.OrderAnnounced({
            account: msg.sender,
            orderType: FlatcoinStructs.OrderType.StableDeposit,
            keeperFee: keeperFee
        });
    }

    /// @notice Announces withdrawal intent for keepers to execute at offchain oracle price.
    /// @dev The deposit amount is taken plus the keeper fee, also in LP tokens.
    /// @param withdrawAmount The amount to withdraw in stable LP tokens.
    /// @param minAmountOut The minimum amount of underlying asset tokens the user expects to receive back.
    /// @param keeperFee The fee the user is paying for keeper transaction execution (in stable LP tokens).
    function announceStableWithdraw(
        uint256 withdrawAmount,
        uint256 minAmountOut,
        uint256 keeperFee
    ) external whenNotPaused {
        uint64 executableAtTime = _prepareAnnouncementOrder(keeperFee);

        IStableModule stableModule = IStableModule(vault.moduleAddress(FlatcoinModuleKeys._STABLE_MODULE_KEY));
        uint256 lpBalance = IERC20Upgradeable(stableModule).balanceOf(msg.sender);

        if (lpBalance < withdrawAmount)
            revert FlatcoinErrors.NotEnoughBalanceForWithdraw(msg.sender, lpBalance, withdrawAmount);

        // Check that the requested minAmountOut is feasible
        {
            uint256 expectedAmountOut = stableModule.stableWithdrawQuote(withdrawAmount);

            if (keeperFee > expectedAmountOut) revert FlatcoinErrors.WithdrawalTooSmall(expectedAmountOut, keeperFee);

            expectedAmountOut -= keeperFee;

            if (expectedAmountOut < minAmountOut) revert FlatcoinErrors.HighSlippage(expectedAmountOut, minAmountOut);

            vault.checkSkewMax({additionalSkew: expectedAmountOut});
        }

        _announcedOrder[msg.sender] = FlatcoinStructs.Order({
            orderType: FlatcoinStructs.OrderType.StableWithdraw,
            orderData: abi.encode(
                FlatcoinStructs.AnnouncedStableWithdraw({withdrawAmount: withdrawAmount, minAmountOut: minAmountOut})
            ),
            keeperFee: keeperFee,
            executableAtTime: executableAtTime
        });

        // Lock the LP tokens belonging to this position so that it can't be transferred to someone else.
        // Locking doesn't require an approval from an account.
        stableModule.lock({account: msg.sender, amount: withdrawAmount});

        emit FlatcoinEvents.OrderAnnounced({
            account: msg.sender,
            orderType: FlatcoinStructs.OrderType.StableWithdraw,
            keeperFee: keeperFee
        });
    }

    /// @notice Announces leverage open intent for keepers to execute at offchain oracle price.
    /// @param margin The amount of collateral to deposit.
    /// @param additionalSize The amount of additional size to open.
    /// @param maxFillPrice The maximum price at which the trade can be executed.
    /// @param keeperFee The fee the user is paying for keeper transaction execution (in collateral tokens).
    function announceLeverageOpen(
        uint256 margin,
        uint256 additionalSize,
        uint256 maxFillPrice,
        uint256 keeperFee
    ) external whenNotPaused {
        ILeverageModule leverageModule = ILeverageModule(vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY));

        uint64 executableAtTime = _prepareAnnouncementOrder(keeperFee);

        vault.checkSkewMax({additionalSkew: additionalSize});

        leverageModule.checkLeverageCriteria(margin, additionalSize);

        (uint256 currentPrice, ) = IOracleModule(vault.moduleAddress(FlatcoinModuleKeys._ORACLE_MODULE_KEY)).getPrice();

        if (maxFillPrice < currentPrice) revert FlatcoinErrors.MaxFillPriceTooLow(maxFillPrice, currentPrice);

        uint256 tradeFee = leverageModule.getTradeFee(additionalSize);

        if (
            ILiquidationModule(vault.moduleAddress(FlatcoinModuleKeys._LIQUIDATION_MODULE_KEY)).getLiquidationMargin(
                additionalSize,
                maxFillPrice
            ) >= margin
        ) revert FlatcoinErrors.PositionCreatesBadDebt();

        _announcedOrder[msg.sender] = FlatcoinStructs.Order({
            orderType: FlatcoinStructs.OrderType.LeverageOpen,
            orderData: abi.encode(
                FlatcoinStructs.AnnouncedLeverageOpen({
                    margin: margin,
                    additionalSize: additionalSize,
                    maxFillPrice: maxFillPrice,
                    tradeFee: tradeFee
                })
            ),
            keeperFee: keeperFee,
            executableAtTime: executableAtTime
        });

        // Sends collateral to the delayed order contract first before it is settled by keepers and sent to the vault
        vault.collateral().safeTransferFrom(msg.sender, address(this), margin + keeperFee + tradeFee);

        emit FlatcoinEvents.OrderAnnounced({
            account: msg.sender,
            orderType: FlatcoinStructs.OrderType.LeverageOpen,
            keeperFee: keeperFee
        });
    }

    /// @notice Announces leverage adjust intent for keepers to execute at offchain oracle price.
    /// @param tokenId The ERC721 token ID of the position.
    /// @param marginAdjustment The amount of margin to deposit or withdraw.
    /// @param additionalSizeAdjustment The amount of additional size to increase or decrease.
    /// @param fillPrice The price at which the trade can be executed.
    /// @param keeperFee The fee the user is paying for keeper transaction execution (in collateral tokens).
    function announceLeverageAdjust(
        uint256 tokenId,
        int256 marginAdjustment,
        int256 additionalSizeAdjustment,
        uint256 fillPrice,
        uint256 keeperFee
    ) external whenNotPaused {
        uint64 executableAtTime = _prepareAnnouncementOrder(keeperFee);

        // If both adjustable parameters are zero, there is nothing to adjust
        if (marginAdjustment == 0 && additionalSizeAdjustment == 0)
            revert FlatcoinErrors.ZeroValue("marginAdjustment|additionalSizeAdjustment");

        ILeverageModule leverageModule = ILeverageModule(vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY));

        // Check that the caller is the owner of the token
        if (leverageModule.ownerOf(tokenId) != msg.sender) revert FlatcoinErrors.NotTokenOwner(tokenId, msg.sender);

        // Trade fee is calculated based on additional size change
        uint256 totalFee;
        {
            uint256 tradeFee;
            (uint256 currentPrice, ) = IOracleModule(vault.moduleAddress(FlatcoinModuleKeys._ORACLE_MODULE_KEY))
                .getPrice();

            // Means increasing or decreasing additional size
            if (additionalSizeAdjustment >= 0) {
                // If additionalSizeAdjustment equals zero, trade fee is zero as well
                tradeFee = leverageModule.getTradeFee(uint256(additionalSizeAdjustment));
                vault.checkSkewMax(uint256(additionalSizeAdjustment));

                if (fillPrice < currentPrice) revert FlatcoinErrors.MaxFillPriceTooLow(fillPrice, currentPrice);
            } else {
                tradeFee = leverageModule.getTradeFee(uint256(additionalSizeAdjustment * -1));

                if (fillPrice > currentPrice) revert FlatcoinErrors.MinFillPriceTooHigh(fillPrice, currentPrice);
            }

            totalFee = tradeFee + keeperFee;
        }

        {
            // New additional size will be either bigger or smaller than current additional size
            // depends on if additionalSizeAdjustment is positive or negative.
            int256 newAdditionalSize = int256(vault.getPosition(tokenId).additionalSize) + additionalSizeAdjustment;

            // If user withdraws margin or changes additional size with no changes to margin, fees are charged from their existing margin.
            int256 newMarginAfterSettlement = leverageModule.getPositionSummary(tokenId).marginAfterSettlement +
                ((marginAdjustment > 0) ? marginAdjustment : marginAdjustment - int256(totalFee));

            // New margin or size can't be negative, which means that they want to withdraw more than they deposited or not enough to pay the fees
            if (newMarginAfterSettlement < 0 || newAdditionalSize < 0)
                revert FlatcoinErrors.ValueNotPositive("newMarginAfterSettlement|newAdditionalSize");

            if (
                ILiquidationModule(vault.moduleAddress(FlatcoinModuleKeys._LIQUIDATION_MODULE_KEY))
                    .getLiquidationMargin(uint256(newAdditionalSize), fillPrice) >= uint256(newMarginAfterSettlement)
            ) revert FlatcoinErrors.PositionCreatesBadDebt();

            // New values can't be less than min margin and min/max leverage requirements.
            leverageModule.checkLeverageCriteria(uint256(newMarginAfterSettlement), uint256(newAdditionalSize));
        }

        _announcedOrder[msg.sender] = FlatcoinStructs.Order({
            orderType: FlatcoinStructs.OrderType.LeverageAdjust,
            orderData: abi.encode(
                FlatcoinStructs.AnnouncedLeverageAdjust({
                    tokenId: tokenId,
                    marginAdjustment: marginAdjustment,
                    additionalSizeAdjustment: additionalSizeAdjustment,
                    fillPrice: fillPrice,
                    tradeFee: totalFee - keeperFee,
                    totalFee: totalFee
                })
            ),
            keeperFee: keeperFee,
            executableAtTime: executableAtTime
        });

        // Lock the NFT belonging to this position so that it can't be transferred to someone else.
        // Locking doesn't require an approval from the leverage trader.
        leverageModule.lock(tokenId);

        // If user increases margin, fees are charged from their account.
        if (marginAdjustment > 0) {
            // Sending positive margin adjustment and both fees from the user to the delayed order contract.
            vault.collateral().safeTransferFrom(msg.sender, address(this), uint256(marginAdjustment) + totalFee);
        }

        emit FlatcoinEvents.OrderAnnounced({
            account: msg.sender,
            orderType: FlatcoinStructs.OrderType.LeverageAdjust,
            keeperFee: keeperFee
        });
    }

    /// @notice Announces leverage close intent for keepers to execute at offchain oracle price.
    /// @param tokenId The ERC721 token ID of the position.
    /// @param minFillPrice The minimum price at which the trade can be executed.
    /// @param keeperFee The fee the user is paying for keeper transaction execution (in collateral tokens).
    function announceLeverageClose(uint256 tokenId, uint256 minFillPrice, uint256 keeperFee) external whenNotPaused {
        uint64 executableAtTime = _prepareAnnouncementOrder(keeperFee);
        uint256 tradeFee;

        ILeverageModule leverageModule = ILeverageModule(vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY));

        // Check that the caller of this function is actually the owner of the token ID.
        // Since `lock` function in leverage module doesn't check for this, we need to do it here.
        if (leverageModule.ownerOf(tokenId) != msg.sender) revert FlatcoinErrors.NotTokenOwner(tokenId, msg.sender);

        {
            uint256 size = vault.getPosition(tokenId).additionalSize;

            // Position needs additional margin to cover the trading fee on closing the position
            tradeFee = leverageModule.getTradeFee(size);

            // Make sure there is enough margin in the position to pay the keeper fee and trading fee
            // This should always pass because the position should get liquidated before the margin becomes too small
            int256 settledMargin = leverageModule.getPositionSummary(tokenId).marginAfterSettlement;

            uint256 totalFee = tradeFee + keeperFee;
            if (settledMargin < int256(totalFee)) revert FlatcoinErrors.NotEnoughMarginForFees(settledMargin, totalFee);

            (uint256 currentPrice, ) = IOracleModule(vault.moduleAddress(FlatcoinModuleKeys._ORACLE_MODULE_KEY))
                .getPrice();

            if (minFillPrice > currentPrice) revert FlatcoinErrors.MinFillPriceTooHigh(minFillPrice, currentPrice);
        }

        _announcedOrder[msg.sender] = FlatcoinStructs.Order({
            orderType: FlatcoinStructs.OrderType.LeverageClose,
            orderData: abi.encode(
                FlatcoinStructs.AnnouncedLeverageClose({
                    tokenId: tokenId,
                    minFillPrice: minFillPrice,
                    tradeFee: tradeFee
                })
            ),
            keeperFee: keeperFee,
            executableAtTime: executableAtTime
        });

        // Lock the NFT belonging to this position so that it can't be transferred to someone else.
        // Locking doesn't require an approval from the leverage trader.
        leverageModule.lock(tokenId);

        emit FlatcoinEvents.OrderAnnounced({
            account: msg.sender,
            orderType: FlatcoinStructs.OrderType.LeverageClose,
            keeperFee: keeperFee
        });
    }

    /////////////////////////////////////////////
    //           Execution Functions           //
    /////////////////////////////////////////////

    /// @notice Executes any valid pending order for an account.
    /// @dev Uses the Pyth network price to execute.
    /// @param account The user account which has a pending deposit.
    /// @param priceUpdateData The Pyth network offchain price oracle update data.
    function executeOrder(
        address account,
        bytes[] calldata priceUpdateData
    )
        external
        payable
        nonReentrant
        whenNotPaused
        updatePythPrice(vault, msg.sender, priceUpdateData)
        orderInvariantChecks(vault)
    {
        // Settle funding fees before executing any order.
        // This is to avoid error related to max caps or max skew reached when the market has been skewed to one side for a long time.
        // This is more important in case the we allow for limit orders in the future.
        vault.settleFundingFees();

        FlatcoinStructs.OrderType orderType = _announcedOrder[account].orderType;

        // If there is no order in store, just return.
        if (orderType == FlatcoinStructs.OrderType.None) return;

        if (orderType == FlatcoinStructs.OrderType.StableDeposit) {
            _executeStableDeposit(account);
        } else if (orderType == FlatcoinStructs.OrderType.StableWithdraw) {
            _executeStableWithdraw(account);
        } else if (orderType == FlatcoinStructs.OrderType.LeverageOpen) {
            _executeLeverageOpen(account);
        } else if (orderType == FlatcoinStructs.OrderType.LeverageClose) {
            _executeLeverageClose(account);
        } else if (orderType == FlatcoinStructs.OrderType.LeverageAdjust) {
            _executeLeverageAdjust(account);
        }
    }

    /// @notice Function to cancel an existing order after it has expired.
    /// @dev This function can be called by anyone.
    /// @param account The user account which has a pending order.
    function cancelExistingOrder(address account) public {
        FlatcoinStructs.Order memory order = _announcedOrder[account];

        // If there is no order in store, just return.
        if (order.orderType == FlatcoinStructs.OrderType.None) return;

        if (block.timestamp <= order.executableAtTime + vault.maxExecutabilityAge())
            revert FlatcoinErrors.OrderHasNotExpired();

        // Delete the order tracker from storage.
        // NOTE: This is done before the transfer of ERC721 NFT to prevent reentrancy attacks.
        delete _announcedOrder[account];

        if (order.orderType == FlatcoinStructs.OrderType.StableDeposit) {
            FlatcoinStructs.AnnouncedStableDeposit memory stableDeposit = abi.decode(
                order.orderData,
                (FlatcoinStructs.AnnouncedStableDeposit)
            );

            // Send collateral back to trader
            vault.collateral().safeTransfer({to: account, value: stableDeposit.depositAmount + order.keeperFee});
        } else if (order.orderType == FlatcoinStructs.OrderType.StableWithdraw) {
            FlatcoinStructs.AnnouncedStableWithdraw memory stableWithdraw = abi.decode(
                order.orderData,
                (FlatcoinStructs.AnnouncedStableWithdraw)
            );

            // Unlock the LP tokens belonging to this position which were locked during announcement.
            IStableModule(vault.moduleAddress(FlatcoinModuleKeys._STABLE_MODULE_KEY)).unlock({
                account: account,
                amount: stableWithdraw.withdrawAmount
            });
        } else if (order.orderType == FlatcoinStructs.OrderType.LeverageOpen) {
            FlatcoinStructs.AnnouncedLeverageOpen memory leverageOpen = abi.decode(
                order.orderData,
                (FlatcoinStructs.AnnouncedLeverageOpen)
            );

            // Send collateral back to trader
            vault.collateral().safeTransfer({
                to: account,
                value: order.keeperFee + leverageOpen.margin + leverageOpen.tradeFee
            });
        } else if (order.orderType == FlatcoinStructs.OrderType.LeverageClose) {
            FlatcoinStructs.AnnouncedLeverageClose memory leverageClose = abi.decode(
                order.orderData,
                (FlatcoinStructs.AnnouncedLeverageClose)
            );

            // Unlock the ERC721 position NFT to allow for transfers.
            ILeverageModule(vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY)).unlock(leverageClose.tokenId);
        } else if (order.orderType == FlatcoinStructs.OrderType.LeverageAdjust) {
            FlatcoinStructs.AnnouncedLeverageAdjust memory leverageAdjust = abi.decode(
                order.orderData,
                (FlatcoinStructs.AnnouncedLeverageAdjust)
            );

            if (leverageAdjust.marginAdjustment > 0) {
                vault.collateral().safeTransfer({
                    to: account,
                    value: uint256(leverageAdjust.marginAdjustment) + leverageAdjust.totalFee
                });
            }

            // Unlock the ERC721 position NFT to allow for transfers.
            ILeverageModule(vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY)).unlock(
                leverageAdjust.tokenId
            );
        }

        emit FlatcoinEvents.OrderCancelled({account: account, orderType: order.orderType});
    }

    /////////////////////////////////////////////
    //       Internal Execution Functions      //
    /////////////////////////////////////////////

    /// @notice User delayed deposit into the stable LP. Mints ERC20 token receipt.
    /// @dev Uses the Pyth network price to execute.
    /// @param account The user account which has a pending deposit.
    /// @return liquidityMinted The amount of stable LP tokens the user receives.
    function _executeStableDeposit(address account) internal returns (uint256 liquidityMinted) {
        FlatcoinStructs.Order memory order = _announcedOrder[account];

        FlatcoinStructs.AnnouncedStableDeposit memory stableDeposit = abi.decode(
            order.orderData,
            (FlatcoinStructs.AnnouncedStableDeposit)
        );

        vault.checkCollateralCap(stableDeposit.depositAmount);

        _prepareExecutionOrder(account, order.executableAtTime);

        liquidityMinted = IStableModule(vault.moduleAddress(FlatcoinModuleKeys._STABLE_MODULE_KEY)).executeDeposit(
            account,
            order.executableAtTime,
            stableDeposit
        );

        // Settle the collateral
        vault.collateral().safeTransfer({to: msg.sender, value: order.keeperFee}); // pay the keeper their fee
        vault.collateral().safeTransfer({to: address(vault), value: stableDeposit.depositAmount}); // transfer collateral to the vault

        emit FlatcoinEvents.OrderExecuted({account: account, orderType: order.orderType, keeperFee: order.keeperFee});
    }

    /// @notice User delayed withdrawal from the stable LP.
    /// @dev Uses the Pyth network price to execute.
    /// @param account The user account which has a pending withdrawal.
    /// @return amountOut The amount of collateral asset tokens the user receives.
    function _executeStableWithdraw(address account) internal returns (uint256 amountOut) {
        FlatcoinStructs.Order memory order = _announcedOrder[account];

        _prepareExecutionOrder(account, order.executableAtTime);

        FlatcoinStructs.AnnouncedStableWithdraw memory stableWithdraw = abi.decode(
            order.orderData,
            (FlatcoinStructs.AnnouncedStableWithdraw)
        );

        uint256 withdrawFee;

        (amountOut, withdrawFee) = IStableModule(vault.moduleAddress(FlatcoinModuleKeys._STABLE_MODULE_KEY))
            .executeWithdraw(account, order.executableAtTime, stableWithdraw);

        uint256 totalFee = order.keeperFee + withdrawFee;

        // Make sure there is enough margin in the position to pay the keeper fee and withdrawal fee
        if (amountOut < totalFee) revert FlatcoinErrors.NotEnoughMarginForFees(int256(amountOut), totalFee);

        // include the fees here to check for slippage
        amountOut -= totalFee;

        if (amountOut < stableWithdraw.minAmountOut)
            revert FlatcoinErrors.HighSlippage(amountOut, stableWithdraw.minAmountOut);

        // Settle the collateral
        vault.updateStableCollateralTotal(int256(withdrawFee)); // pay the withdrawal fee to stable LPs
        vault.sendCollateral({to: msg.sender, amount: order.keeperFee}); // pay the keeper their fee
        vault.sendCollateral({to: account, amount: amountOut}); // transfer remaining amount to the trader

        emit FlatcoinEvents.OrderExecuted({account: account, orderType: order.orderType, keeperFee: order.keeperFee});
    }

    /// @notice Execution of user delayed leverage open order. Mints ERC721 token receipt.
    /// @dev Uses the Pyth network price to execute.
    /// @param account The user account which has a pending order.
    /// @return tokenId The ERC721 token ID of the position.
    function _executeLeverageOpen(address account) internal returns (uint256 tokenId) {
        FlatcoinStructs.Order memory order = _announcedOrder[account];
        FlatcoinStructs.AnnouncedLeverageOpen memory announcedOpen = abi.decode(
            order.orderData,
            (FlatcoinStructs.AnnouncedLeverageOpen)
        );

        _prepareExecutionOrder(account, order.executableAtTime);

        vault.collateral().safeTransfer({
            to: address(vault),
            value: announcedOpen.margin + announcedOpen.tradeFee + order.keeperFee
        }); // transfer collateral + fees to the vault

        tokenId = ILeverageModule(vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY)).executeOpen({
            account: account,
            keeper: msg.sender,
            order: order
        });

        emit FlatcoinEvents.OrderExecuted({account: account, orderType: order.orderType, keeperFee: order.keeperFee});
    }

    /// @notice Execution of user delayed leverage adjust order.
    /// @dev Uses the Pyth network price to execute.
    /// @param account The user account which has a pending order.
    function _executeLeverageAdjust(address account) internal {
        FlatcoinStructs.Order memory order = _announcedOrder[account];
        FlatcoinStructs.AnnouncedLeverageAdjust memory leverageAdjust = abi.decode(
            order.orderData,
            (FlatcoinStructs.AnnouncedLeverageAdjust)
        );

        _prepareExecutionOrder(account, order.executableAtTime);

        ILeverageModule(vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY)).executeAdjust({
            account: account,
            keeper: msg.sender,
            order: order
        });

        if (leverageAdjust.marginAdjustment > 0) {
            // Sending positive margin adjustment and fees from delayed order contract to the vault
            vault.collateral().safeTransfer({
                to: address(vault),
                value: uint256(leverageAdjust.marginAdjustment) + leverageAdjust.tradeFee + order.keeperFee
            });
        }

        emit FlatcoinEvents.OrderExecuted({account: account, orderType: order.orderType, keeperFee: order.keeperFee});
    }

    /// @notice Execution of user delayed leverage close order. Burns ERC721 token receipt.
    /// @dev Uses the Pyth network price to execute.
    /// @param account The user account which has a pending order.
    /// @return settledMargin The amount of margin settled from the position.
    function _executeLeverageClose(address account) internal returns (int256 settledMargin) {
        FlatcoinStructs.Order memory order = _announcedOrder[account];

        _prepareExecutionOrder(account, order.executableAtTime);

        settledMargin = ILeverageModule(vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY)).executeClose({
            account: account,
            keeper: msg.sender,
            order: order
        });

        emit FlatcoinEvents.OrderExecuted({account: account, orderType: order.orderType, keeperFee: order.keeperFee});
    }

    /// @dev This function HAS to be called as soon as the transaction flow enters an announce function.
    function _prepareAnnouncementOrder(uint256 keeperFee) internal returns (uint64 executableAtTime) {
        // Settle funding fees to not encounter the `MaxSkewReached` error.
        // This error could happen if the funding fees are not settled for a long time and the market is skewed long
        // for a long time.
        vault.settleFundingFees();

        if (keeperFee < IKeeperFee(vault.moduleAddress(FlatcoinModuleKeys._KEEPER_FEE_MODULE_KEY)).getKeeperFee())
            revert FlatcoinErrors.InvalidFee(keeperFee);

        // If the user has an existing pending order that expired, then cancel it.
        cancelExistingOrder(msg.sender);

        executableAtTime = uint64(block.timestamp + vault.minExecutabilityAge());
    }

    /// @dev This function HAS to be called as soon as the transaction flow enters an execute function.
    function _prepareExecutionOrder(address account, uint256 executableAtTime) internal {
        if (block.timestamp > executableAtTime + vault.maxExecutabilityAge()) revert FlatcoinErrors.OrderHasExpired();

        // Check that the minimum time delay is reached before execution
        if (block.timestamp < executableAtTime) revert FlatcoinErrors.ExecutableTimeNotReached(executableAtTime);

        // Delete the order tracker from storage.
        delete _announcedOrder[account];
    }

    /////////////////////////////////////////////
    //             View Functions              //
    /////////////////////////////////////////////

    /// @notice Getter for the announced order of an account
    /// @param account The user account which has a pending order
    /// @return order The order struct
    function getAnnouncedOrder(address account) external view returns (FlatcoinStructs.Order memory order) {
        return _announcedOrder[account];
    }

    /// @notice Checks whether a user announced order has expired executability time or not
    /// @param account The user account which has a pending order
    /// @return expired True if the order has expired, false otherwise
    function hasOrderExpired(address account) public view returns (bool expired) {
        uint256 executableAtTime = _announcedOrder[account].executableAtTime;

        if (executableAtTime <= 0) revert FlatcoinErrors.ZeroValue("executableAtTime");

        expired = (executableAtTime + vault.maxExecutabilityAge() >= block.timestamp) ? false : true;
    }
}
