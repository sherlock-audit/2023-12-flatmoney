// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {ModuleUpgradeable} from "./abstracts/ModuleUpgradeable.sol";
import {DecimalMath} from "./libraries/DecimalMath.sol";
import {FlatcoinErrors} from "./libraries/FlatcoinErrors.sol";
import {FlatcoinModuleKeys} from "./libraries/FlatcoinModuleKeys.sol";
import {ERC20LockableUpgradeable} from "./misc/ERC20LockableUpgradeable.sol";

import {IFlatcoinVault} from "./interfaces/IFlatcoinVault.sol";

/// @title PointsModule
/// @author dHEDGE
/// @notice Module for awarding points as an incentive.
contract PointsModule is ModuleUpgradeable, ERC20LockableUpgradeable {
    using DecimalMath for uint256;

    address public treasury;

    /// @notice The duration of the unlock tax vesting period
    uint256 public unlockTaxVest;

    /// @notice Used to calculate points to mint when a user opens a leveraged position
    uint256 public pointsPerSize;

    /// @notice Used to calculate points to mint when a user deposits an amount of collateral to the flatcoin
    uint256 public pointsPerDeposit;

    /// @notice Time when user’s points will have 0% unlock tax
    mapping(address account => uint256 unlockTime) public unlockTime;

    struct MintPoints {
        address to;
        uint256 amount;
    }

    /// @dev To prevent the implementation contract from being used, we invoke the _disableInitializers
    /// function in the constructor to automatically lock it when it is deployed.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Function to initialize this contract.
    function initialize(
        IFlatcoinVault _flatcoinVault,
        address _treasury,
        uint256 _unlockTaxVest,
        uint256 _pointsPerSize,
        uint256 _pointsPerDeposit
    ) external initializer {
        if (address(_flatcoinVault) == address(0)) revert FlatcoinErrors.ZeroAddress("flatcoinVault");

        __Module_init(FlatcoinModuleKeys._POINTS_MODULE_KEY, _flatcoinVault);
        __ERC20_init("Flat.money Points", "FMP");

        setTreasury(_treasury);
        setPointsVest(_unlockTaxVest, _pointsPerSize, _pointsPerDeposit);
    }

    /////////////////////////////////////////////
    //         Public Write Functions          //
    /////////////////////////////////////////////

    /// @notice Mints locked points to the user account when a user opens a leveraged position (uses pointsPerSize).
    ///         The points start a 12 month unlock tax (update unlockTime).
    /// @dev The function will not revert if no points are minted because it's called by the flatcoin contracts.
    function mintLeverageOpen(address to, uint256 size) external onlyAuthorizedModule {
        if (pointsPerSize == 0) return; // no incentives set on leverage open

        uint256 amount = size._multiplyDecimal(pointsPerSize);
        if (amount < 1e6) return; // ignore dust amounts (could happen on adjustment)

        _mintTo(to, amount);
    }

    /// @notice Mints locked points to the user account when a user deposits to the flatcoin (uses pointsPerDeposit).
    ///         The points start a 12 month unlock tax (update unlockTime).
    /// @dev The function will not revert if no points are minted because it's called by the flatcoin contracts.
    function mintDeposit(address to, uint256 depositAmount) external onlyAuthorizedModule {
        if (pointsPerDeposit == 0) return; // no incentives set on flatcoin LP deposit

        uint256 amount = depositAmount._multiplyDecimal(pointsPerDeposit);
        if (amount < 1e6) return; // ignore dust amounts

        _mintTo(to, amount);
    }

    /// @notice Owner can mint points to any account. This can be used to distribute points to competition winners and other reward incentives.
    ///         The points start a 12 month unlock tax (update unlockTime).
    function mintTo(MintPoints calldata _mintPoints) external onlyOwner {
        _mintTo(_mintPoints.to, _mintPoints.amount);
    }

    /// @notice Owner can mint points to multiple accounts
    function mintToMultiple(MintPoints[] calldata _mintPoints) external onlyOwner {
        for (uint256 i = 0; i < _mintPoints.length; i++) {
            _mintTo(_mintPoints[i].to, _mintPoints[i].amount);
        }
    }

    /// @notice Unlocks all of sender’s locked tokens. Sends any taxed points to the treasury.
    function unlockAll() public {
        _unlock(type(uint256).max);
    }

    /// @notice Unlocks a specified amount of the sender’s locked tokens. Sends any taxed points to the treasury.
    function unlock(uint256 amount) public {
        _unlock(amount);
    }

    /////////////////////////////////////////////
    //             View Functions              //
    /////////////////////////////////////////////

    /// @notice Calculates the unlock tax for a specific account.
    ///         If a user has 100 points that have vested for 6 months (50% tax), then it returns 0.5e18.
    ///         If this user earns another 100 points, then the new unlock tax should be 75% or 0.75e18.
    ///         This tax can be calculated by using and modifying the unlockTime when the points are minted to an account.
    function getUnlockTax(address account) public view returns (uint256 unlockTax) {
        if (unlockTime[account] <= block.timestamp) return 0;

        uint256 timeLeft = unlockTime[account] - block.timestamp;

        unlockTax = timeLeft._divideDecimal(unlockTaxVest);

        assert(unlockTax <= 1e18);
    }

    /// @notice Returns an account's locked token balance
    function lockedBalance(address account) public view returns (uint256 amount) {
        return _lockedAmount[account];
    }

    /////////////////////////////////////////////
    //           Internal Functions            //
    /////////////////////////////////////////////

    /// @notice Sets the unlock time for newly minted points.
    /// @dev    If the user has existing locked points, then the new unlock time is calculated based on the existing locked points.
    ///         The newly minted points are included in the `lockedAmount` calculation.
    function _setMintUnlockTime(address account, uint256 mintAmount) internal returns (uint256 newUnlockTime) {
        uint256 lockedAmount = _lockedAmount[account];
        uint256 unlockTimeBefore = unlockTime[account];

        if (unlockTimeBefore <= block.timestamp) {
            newUnlockTime = block.timestamp + unlockTaxVest;
        } else {
            uint256 newUnlockTimeAmount = (block.timestamp + unlockTaxVest) * mintAmount;
            uint256 oldUnlockTimeAmount = unlockTimeBefore * (lockedAmount - mintAmount);
            newUnlockTime = (newUnlockTimeAmount + oldUnlockTimeAmount) / lockedAmount;
        }

        unlockTime[account] = newUnlockTime;
    }

    function _mintTo(address to, uint256 amount) internal {
        if (amount < 1e6) {
            // avoids potential precision errors on unlock time calculations
            revert FlatcoinErrors.MintAmountTooLow(amount);
        }

        uint256 _unlockTime = unlockTime[to];

        if (_unlockTime > 0 && _unlockTime <= block.timestamp) {
            // lock has expired, so unlock existing tokens first
            _unlock(to, _lockedAmount[to]);
        }
        _mint(to, amount);
        _lock(to, amount);
        _setMintUnlockTime(to, amount);
    }

    /// @notice Unlocks the sender’s locked tokens.
    function _unlock(uint256 amount) internal {
        uint256 unlockTax = getUnlockTax(msg.sender);
        uint256 lockedAmount = _lockedAmount[msg.sender];

        if (amount == type(uint256).max) amount = lockedAmount;

        if (lockedAmount == amount) unlockTime[msg.sender] = 0;

        _unlock(msg.sender, amount);

        if (unlockTax > 0) {
            uint256 treasuryAmount = amount._multiplyDecimal(unlockTax);
            _transfer(msg.sender, treasury, treasuryAmount);
        }
    }

    /// @notice Sets the treasury address
    function setTreasury(address _treasury) public onlyOwner {
        if (_treasury == address(0)) revert FlatcoinErrors.ZeroAddress("treasury");

        treasury = _treasury;
    }

    /// @notice Sets the points unlock tax vesting period and minted points per trade
    /// @dev There are no restrictions on the settings
    /// @param _unlockTaxVest The duration of the unlock tax vesting period
    /// @param _pointsPerSize Used to calculate points to mint when a user opens a leveraged position
    /// @param _pointsPerDeposit Used to calculate points to mint when a user deposits an amount of collateral to the flatcoin
    function setPointsVest(uint256 _unlockTaxVest, uint256 _pointsPerSize, uint256 _pointsPerDeposit) public onlyOwner {
        unlockTaxVest = _unlockTaxVest;
        pointsPerSize = _pointsPerSize;
        pointsPerDeposit = _pointsPerDeposit;
    }
}
