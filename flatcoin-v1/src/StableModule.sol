// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
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

contract StableModule is IStableModule, ModuleUpgradeable, ERC20LockableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using PerpMath for int256;
    using PerpMath for uint256;

    // TODO: Make the min deposit in USD value (eg $50).
    // TODO: Move these to `VautSettings` contract.
    uint256 public constant MIN_DEPOSIT = 10_000; // minimum collateral deposit amount
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
        __ERC20_init("Flatcoin V1", "FLAT");
        __Module_init(FlatcoinModuleKeys._STABLE_MODULE_KEY, _vault);

        setStableWithdrawFee(_stableWithdrawFee);
    }

    /////////////////////////////////////////////
    //         Public Write Functions          //
    /////////////////////////////////////////////

    // TODO: Minimum amount out check
    /// @notice User delayed deposit into the stable LP. Mints ERC20 token receipt.
    /// @dev Uses the Pyth network price to execute
    /// @param account The usser account which has a pending deposit
    /// @param announcedDeposit The pending order
    function executeDeposit(
        address account,
        uint64 executableAtTime,
        FlatcoinStructs.AnnouncedStableDeposit calldata announcedDeposit
    ) external whenNotPaused onlyAuthorizedModule returns (uint256 liquidityMinted) {
        uint256 depositAmount = announcedDeposit.depositAmount;

        // Make sure the oracle price is after the order executability time
        uint32 maxAge = uint32(block.timestamp - executableAtTime);

        liquidityMinted = (depositAmount * (10 ** decimals())) / stableCollateralPerShare(maxAge);

        if (liquidityMinted < announcedDeposit.minAmountOut)
            revert FlatcoinErrors.HighSlippage(liquidityMinted, announcedDeposit.minAmountOut);

        _mint(account, liquidityMinted);

        vault.updateStableCollateralTotal(int256(depositAmount));

        if (totalSupply() < MIN_LIQUIDITY)
            revert FlatcoinErrors.AmountTooSmall({amount: totalSupply(), minAmount: MIN_LIQUIDITY});

        // Mint points
        IPointsModule pointsModule = IPointsModule(vault.moduleAddress(FlatcoinModuleKeys._POINTS_MODULE_KEY));
        pointsModule.mintDeposit(account, announcedDeposit.depositAmount);

        emit FlatcoinEvents.Deposit(account, depositAmount, liquidityMinted);
    }

    /// @notice User delayed withdrawal from the stable LP. Burns ERC20 token receipt.
    /// @dev Uses the Pyth network price to execute
    /// @param account The usser account which has a pending withdrawal
    /// @param announcedWithdraw The pending order
    function executeWithdraw(
        address account,
        uint64 executableAtTime,
        FlatcoinStructs.AnnouncedStableWithdraw calldata announcedWithdraw
    ) external whenNotPaused onlyAuthorizedModule returns (uint256 amountOut, uint256 withdrawFee) {
        uint256 withdrawAmount = announcedWithdraw.withdrawAmount;

        // Make sure the oracle price is after the order executability time
        uint32 maxAge = uint32(block.timestamp - executableAtTime);

        uint256 stableCollateralPerShareBefore = stableCollateralPerShare(maxAge);
        amountOut = (withdrawAmount * stableCollateralPerShareBefore) / (10 ** decimals());

        // Unlock the locked LP tokens before burning.
        // This is because if the amount to be burned is locked, the burn will fail due to `_beforeTokenTransfer`.
        _unlock(account, withdrawAmount);

        _burn(account, withdrawAmount);

        vault.updateStableCollateralTotal(-int256(amountOut));

        uint256 stableCollateralPerShareAfter = stableCollateralPerShare(maxAge);

        // Check that there is no significant impact on stable token price
        // This should never happen and means that too much value or not enough value was withdrawn
        // TODO: Verify scenarios where this difference is more than just a rounding error >1
        if (totalSupply() > 0) {
            if (
                stableCollateralPerShareAfter < stableCollateralPerShareBefore - 1e6 ||
                stableCollateralPerShareAfter > stableCollateralPerShareBefore + 1e6
            ) revert FlatcoinErrors.PriceImpactDuringWithdraw();

            // don't apply the withdraw fee if it's the final withdrawal
            withdrawFee = (stableWithdrawFee * amountOut) / 1e18;
            vault.checkSkewMax({additionalSkew: 0}); // additionalSkew = 0 because withdrawal was already processed above
        } else {
            // need to check there are no longs open before allowing full system withdrawal
            uint256 sizeOpenedTotal = vault.getVaultSummary().globalPositions.sizeOpenedTotal;
            if (sizeOpenedTotal != 0) revert FlatcoinErrors.MaxSkewReached(sizeOpenedTotal);
            if (stableCollateralPerShareAfter != 1e18) revert FlatcoinErrors.PriceImpactDuringFullWithdraw();
        }

        // DISCUSS: Why is this necessary? To deal with inflation attacks?
        // If so, this is unnecessary given that we are manually accounting for the collateral amount.
        // require(totalSupply() >= 10_000, "SM: Minimum liquidity must remain");

        emit FlatcoinEvents.Withdraw(account, amountOut, withdrawAmount);
    }

    function lock(address account, uint256 amount) public onlyAuthorizedModule {
        _lock(account, amount);
    }

    function unlock(address account, uint256 amount) public onlyAuthorizedModule {
        _unlock(account, amount);
    }

    /////////////////////////////////////////////
    //             View Functions              //
    /////////////////////////////////////////////

    /// @notice Total collateral available for withdrawal
    /// @dev Balance takes into account trader profit and loss and funding rate
    function stableCollateralTotalAfterSettlement() public view returns (uint256 stableCollateralBalance) {
        stableCollateralBalance = stableCollateralTotalAfterSettlement({maxAge: type(uint32).max});
    }

    // TODO: Utilise `maxAge` for offchain orders.
    /// @param maxAge The oldest price oracle timestamp that can be used. Set to 0 to ignore.
    function stableCollateralTotalAfterSettlement(uint32 maxAge) public view returns (uint256 stableCollateralBalance) {
        // Assumption => pnlTotal = pnlLong + fundingAccruedLong
        // The assumption is based on the fact that stable LPs are the counterparty to leverage traders.
        // If the `pnlLong` is +ve that means the traders won and the LPs lost between the last funding rate update and now.
        // Similary if the `fundingAccruedLong` is +ve that means the market was skewed short-side.
        // When we combine these two terms, we get the total profit/loss of the leverage traders.
        // NOTE: This function if called after settlement returns only the PnL as funding has already been adjusted
        //      due to calling `_settleFundingFees()`. Although this still means `netTotal` includes the funding
        //      adjusted long PnL, it might not be clear to the reader of the code.
        int256 netTotal = ILeverageModule(vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY))
            .fundingAdjustedLongPnLTotal({maxAge: maxAge});

        // The flatcoin LPs are the counterparty to the leverage traders.
        // So when the traders win, the flatcoin LPs lose and vice versa.
        // Therefore we subtract the leverage trader profits and add the losses
        int256 totalAfterSettlement = int256(vault.stableCollateralTotal()) - netTotal;

        if (totalAfterSettlement < 0) {
            stableCollateralBalance = 0;
        } else {
            stableCollateralBalance = uint256(totalAfterSettlement);
        }
    }

    /// @dev Returns in 18 decimals (1e18 = 1 collateral token per share token)
    function stableCollateralPerShare() public view returns (uint256 collateralPerShare) {
        collateralPerShare = stableCollateralPerShare({maxAge: type(uint32).max});
    }

    /// @param maxAge The oldest price oracle timestamp that can be used. Set to 0 to ignore.
    function stableCollateralPerShare(uint32 maxAge) public view returns (uint256 collateralPerShare) {
        // DISCUSS: Explore if this function can return negative values and if so, what's the implication.
        uint256 totalSupply = totalSupply();

        if (totalSupply > 0) {
            uint256 stableBalance = stableCollateralTotalAfterSettlement(maxAge);

            collateralPerShare = (stableBalance * (10 ** decimals())) / totalSupply;
        } else {
            // no shares have been minted yet
            collateralPerShare = 1e18;
        }
    }

    /// @notice Quoter function for getting the stable deposit amount out
    function stableDepositQuote(uint256 depositAmount) public view returns (uint256 amountOut) {
        amountOut = (depositAmount * (10 ** decimals())) / stableCollateralPerShare();
    }

    /// @notice Quoter function for getting the stable withdraw amount out
    function stableWithdrawQuote(uint256 withdrawAmount) public view returns (uint256 amountOut) {
        amountOut = (withdrawAmount * stableCollateralPerShare()) / (10 ** decimals());

        // Take out the withdrawal fee
        amountOut -= (amountOut * stableWithdrawFee) / 1e18;
    }

    function getLockedAmount(address account) public view returns (uint256 amountLocked) {
        return _lockedAmount[account];
    }

    /////////////////////////////////////////////
    //             Owner Functions             //
    /////////////////////////////////////////////

    /// @notice Setter for the stable withdraw fee
    /// @dev Fees can be set to 0 if needed
    function setStableWithdrawFee(uint256 _stableWithdrawFee) public onlyOwner {
        // set fee cap to max 1%
        if (_stableWithdrawFee > 0.01e18) revert FlatcoinErrors.InvalidFee(_stableWithdrawFee);

        stableWithdrawFee = _stableWithdrawFee;
    }
}
