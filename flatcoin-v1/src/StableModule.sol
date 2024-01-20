// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {SafeCastUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/math/SafeCastUpgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {ERC20LockableUpgradeable} from "./misc/ERC20LockableUpgradeable.sol";

import {PerpMath} from "./libraries/PerpMath.sol";
import {FlatcoinStructs} from "./libraries/FlatcoinStructs.sol";
import {FlatcoinErrors} from "./libraries/FlatcoinErrors.sol";
import {FlatcoinModuleKeys} from "./libraries/FlatcoinModuleKeys.sol";
import {FlatcoinEvents} from "./libraries/FlatcoinEvents.sol";
import {ModuleUpgradeable} from "./abstracts/ModuleUpgradeable.sol";

import {IFlatcoinVault} from "./interfaces/IFlatcoinVault.sol";
import {ILeverageModule} from "./interfaces/ILeverageModule.sol";
import {IStableModule} from "./interfaces/IStableModule.sol";
import {IPointsModule} from "./interfaces/IPointsModule.sol";

/// @title StableModule
/// @author dHEDGE
/// @notice Contains functions to handle stable LP deposits and withdrawals.
contract StableModule is IStableModule, ModuleUpgradeable, ERC20LockableUpgradeable {
    using SafeCastUpgradeable for *;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using PerpMath for int256;
    using PerpMath for uint256;

    uint256 public constant MIN_LIQUIDITY = 10_000; // minimum totalSupply that is allowable

    /// @notice Fee for stable LP redemptions.
    /// @dev 1e18 = 100%
    uint256 public stableWithdrawFee;

    /// @dev To prevent the implementation contract from being used, we invoke the _disableInitializers
    /// function in the constructor to automatically lock it when it is deployed.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Function to initialize this contract.
    function initialize(IFlatcoinVault _vault, uint256 _stableWithdrawFee) external initializer {
        __Module_init(FlatcoinModuleKeys._STABLE_MODULE_KEY, _vault);
        __ERC20_init("Flatmoney", "UNIT");

        setStableWithdrawFee(_stableWithdrawFee);
    }

    /////////////////////////////////////////////
    //         External Write Functions        //
    /////////////////////////////////////////////

    /// @notice User delayed deposit into the stable LP. Mints ERC20 token receipt.
    /// @dev Needs to be used in conjunction with DelayedOrder module.
    /// @param _account The usser account which has a pending deposit.
    /// @param _executableAtTime The time at which the order can be executed.
    /// @param _announcedDeposit The pending order.
    /// @return _liquidityMinted The amount of LP tokens minted.
    function executeDeposit(
        address _account,
        uint64 _executableAtTime,
        FlatcoinStructs.AnnouncedStableDeposit calldata _announcedDeposit
    ) external whenNotPaused onlyAuthorizedModule returns (uint256 _liquidityMinted) {
        uint256 depositAmount = _announcedDeposit.depositAmount;

        uint32 maxAge = _getMaxAge(_executableAtTime);

        _liquidityMinted = (depositAmount * (10 ** decimals())) / stableCollateralPerShare(maxAge);

        if (_liquidityMinted < _announcedDeposit.minAmountOut)
            revert FlatcoinErrors.HighSlippage(_liquidityMinted, _announcedDeposit.minAmountOut);

        _mint(_account, _liquidityMinted);

        vault.updateStableCollateralTotal(int256(depositAmount));

        if (totalSupply() < MIN_LIQUIDITY)
            revert FlatcoinErrors.AmountTooSmall({amount: totalSupply(), minAmount: MIN_LIQUIDITY});

        // Mint points
        IPointsModule pointsModule = IPointsModule(vault.moduleAddress(FlatcoinModuleKeys._POINTS_MODULE_KEY));
        pointsModule.mintDeposit(_account, _announcedDeposit.depositAmount);

        emit FlatcoinEvents.Deposit(_account, depositAmount, _liquidityMinted);
    }

    /// @notice User delayed withdrawal from the stable LP. Burns ERC20 token receipt.
    /// @dev Needs to be used in conjunction with DelayedOrder module.
    /// @param _account The usser account which has a pending withdrawal.
    /// @param _executableAtTime The time at which the order can be executed.
    /// @param _announcedWithdraw The pending order.
    /// @return _amountOut The amount of collateral withdrawn.
    /// @return _withdrawFee The fee paid to the remaining LPs.
    function executeWithdraw(
        address _account,
        uint64 _executableAtTime,
        FlatcoinStructs.AnnouncedStableWithdraw calldata _announcedWithdraw
    ) external whenNotPaused onlyAuthorizedModule returns (uint256 _amountOut, uint256 _withdrawFee) {
        uint256 withdrawAmount = _announcedWithdraw.withdrawAmount;

        uint32 maxAge = _getMaxAge(_executableAtTime);

        uint256 stableCollateralPerShareBefore = stableCollateralPerShare(maxAge);
        _amountOut = (withdrawAmount * stableCollateralPerShareBefore) / (10 ** decimals());

        // Unlock the locked LP tokens before burning.
        // This is because if the amount to be burned is locked, the burn will fail due to `_beforeTokenTransfer`.
        _unlock(_account, withdrawAmount);

        _burn(_account, withdrawAmount);

        vault.updateStableCollateralTotal(-int256(_amountOut));

        uint256 stableCollateralPerShareAfter = stableCollateralPerShare(maxAge);

        // Check that there is no significant impact on stable token price.
        // This should never happen and means that too much value or not enough value was withdrawn.
        if (totalSupply() > 0) {
            if (
                stableCollateralPerShareAfter < stableCollateralPerShareBefore - 1e6 ||
                stableCollateralPerShareAfter > stableCollateralPerShareBefore + 1e6
            ) revert FlatcoinErrors.PriceImpactDuringWithdraw();

            // Apply the withdraw fee if it's not the final withdrawal.
            _withdrawFee = (stableWithdrawFee * _amountOut) / 1e18;

            // additionalSkew = 0 because withdrawal was already processed above.
            vault.checkSkewMax({additionalSkew: 0});
        } else {
            // Need to check there are no longs open before allowing full system withdrawal.
            uint256 sizeOpenedTotal = vault.getVaultSummary().globalPositions.sizeOpenedTotal;

            if (sizeOpenedTotal != 0) revert FlatcoinErrors.MaxSkewReached(sizeOpenedTotal);
            if (stableCollateralPerShareAfter != 1e18) revert FlatcoinErrors.PriceImpactDuringFullWithdraw();
        }

        emit FlatcoinEvents.Withdraw(_account, _amountOut, withdrawAmount);
    }

    /// @notice Function to lock a certain amount of an account's LP tokens.
    /// @dev This function is used to lock LP tokens when an account announces a delayed order.
    /// @param _account The account to lock the LP tokens from.
    /// @param _amount The amount of LP tokens to lock.
    function lock(address _account, uint256 _amount) public onlyAuthorizedModule {
        _lock(_account, _amount);
    }

    /// @notice Function to unlock a certain amount of an account's LP tokens.
    /// @dev This function is used to unlock LP tokens when an account cancels a delayed order
    ///      or when an order is executed.
    /// @param _account The account to unlock the LP tokens from.
    /// @param _amount The amount of LP tokens to unlock.
    function unlock(address _account, uint256 _amount) public onlyAuthorizedModule {
        _unlock(_account, _amount);
    }

    /////////////////////////////////////////////
    //             View Functions              //
    /////////////////////////////////////////////

    /// @notice Total collateral available for withdrawal.
    /// @dev Balance takes into account trader profit and loss and funding rate.
    /// @return _stableCollateralBalance The total collateral available for withdrawal.
    function stableCollateralTotalAfterSettlement() public view returns (uint256 _stableCollateralBalance) {
        return stableCollateralTotalAfterSettlement({_maxAge: type(uint32).max});
    }

    /// @notice Function to calculate total stable side collateral after accounting for trader profit and loss and funding fees.
    /// @param _maxAge The oldest price oracle timestamp that can be used. Set to 0 to ignore.
    /// @return _stableCollateralBalance The total collateral available for withdrawal.
    function stableCollateralTotalAfterSettlement(
        uint32 _maxAge
    ) public view returns (uint256 _stableCollateralBalance) {
        // Assumption => pnlTotal = pnlLong + fundingAccruedLong
        // The assumption is based on the fact that stable LPs are the counterparty to leverage traders.
        // If the `pnlLong` is +ve that means the traders won and the LPs lost between the last funding rate update and now.
        // Similary if the `fundingAccruedLong` is +ve that means the market was skewed short-side.
        // When we combine these two terms, we get the total profit/loss of the leverage traders.
        // NOTE: This function if called after settlement returns only the PnL as funding has already been adjusted
        //      due to calling `_settleFundingFees()`. Although this still means `netTotal` includes the funding
        //      adjusted long PnL, it might not be clear to the reader of the code.
        int256 netTotal = ILeverageModule(vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY))
            .fundingAdjustedLongPnLTotal({maxAge: _maxAge});

        // The flatcoin LPs are the counterparty to the leverage traders.
        // So when the traders win, the flatcoin LPs lose and vice versa.
        // Therefore we subtract the leverage trader profits and add the losses
        int256 totalAfterSettlement = int256(vault.stableCollateralTotal()) - netTotal;

        if (totalAfterSettlement < 0) {
            _stableCollateralBalance = 0;
        } else {
            _stableCollateralBalance = uint256(totalAfterSettlement);
        }
    }

    /// @notice Function to calculate the collateral per share.
    /// @return _collateralPerShare The collateral per share.
    function stableCollateralPerShare() public view returns (uint256 _collateralPerShare) {
        return stableCollateralPerShare({_maxAge: type(uint32).max});
    }

    /// @notice Function to calculate the collateral per share.
    /// @param _maxAge The oldest price oracle timestamp that can be used.
    /// @return _collateralPerShare The collateral per share.
    function stableCollateralPerShare(uint32 _maxAge) public view returns (uint256 _collateralPerShare) {
        uint256 totalSupply = totalSupply();

        if (totalSupply > 0) {
            uint256 stableBalance = stableCollateralTotalAfterSettlement(_maxAge);

            _collateralPerShare = (stableBalance * (10 ** decimals())) / totalSupply;
        } else {
            // no shares have been minted yet
            _collateralPerShare = 1e18;
        }
    }

    /// @notice Quoter function for getting the stable deposit amount out.
    /// @param _depositAmount The amount of collateral to deposit.
    /// @return _amountOut The amount of LP tokens minted.
    function stableDepositQuote(uint256 _depositAmount) public view returns (uint256 _amountOut) {
        return (_depositAmount * (10 ** decimals())) / stableCollateralPerShare();
    }

    /// @notice Quoter function for getting the stable withdraw amount out.
    /// @param _withdrawAmount The amount of LP tokens to withdraw.
    /// @return _amountOut The amount of collateral withdrawn.
    function stableWithdrawQuote(uint256 _withdrawAmount) public view returns (uint256 _amountOut) {
        _amountOut = (_withdrawAmount * stableCollateralPerShare()) / (10 ** decimals());

        // Take out the withdrawal fee
        _amountOut -= (_amountOut * stableWithdrawFee) / 1e18;
    }

    /// @notice Function to get the locked amount of an account.
    /// @param _account The account to get the locked amount for.
    /// @return _amountLocked The amount of LP tokens locked.
    function getLockedAmount(address _account) public view returns (uint256 _amountLocked) {
        return _lockedAmount[_account];
    }

    /////////////////////////////////////////////
    //            Internal Functions           //
    /////////////////////////////////////////////

    /// @notice Returns the maximum age of the oracle price to be used.
    /// @param _executableAtTime The time at which the order is executable.
    /// @return _maxAge The maximum age of the oracle price to be used.
    function _getMaxAge(uint64 _executableAtTime) internal view returns (uint32 _maxAge) {
        return (block.timestamp - _executableAtTime).toUint32();
    }

    /////////////////////////////////////////////
    //             Owner Functions             //
    /////////////////////////////////////////////

    /// @notice Setter for the stable withdraw fee.
    /// @dev Fees can be set to 0 if needed.
    /// @param _stableWithdrawFee The new stable withdraw fee.
    function setStableWithdrawFee(uint256 _stableWithdrawFee) public onlyOwner {
        // Set fee cap to max 1%.
        // This is to avoid fat fingering but if any change is needed, the owner needs to
        // upgrade this module.
        if (_stableWithdrawFee > 0.01e18) revert FlatcoinErrors.InvalidFee(_stableWithdrawFee);

        stableWithdrawFee = _stableWithdrawFee;
    }
}
