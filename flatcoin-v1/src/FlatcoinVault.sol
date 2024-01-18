// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";

import {FlatcoinErrors} from "./libraries/FlatcoinErrors.sol";
import {FlatcoinStructs} from "./libraries/FlatcoinStructs.sol";
import {PerpMath} from "./libraries/PerpMath.sol";

import {IFlatcoinVault} from "./interfaces/IFlatcoinVault.sol";

/// @title FlatcoinVault
/// @notice Contains state to be reused by different modules of the system.
/// @author dHEDGE
/// @dev By holding all the deposit collateral in a single contract
/// then both stable LPs can withdraw collateral without waiting for
/// leverage positions to settle.
/// @dev Stores other related contract address pointers
contract FlatcoinVault is IFlatcoinVault, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice The collateral token address.
    IERC20Upgradeable public collateral;

    /// @notice The last market skew recomputation timestamp.
    uint64 public lastRecomputedFundingTimestamp;

    /// @notice The last recomputed funding rate.
    int256 public lastRecomputedFundingRate;

    /// @notice Sum of funding rate over the entire lifetime of the market.
    int256 public cumulativeFundingRate;

    /// @notice Total collateral deposited by users minting the flatcoin.
    /// @dev This value is adjusted by due to funding fee payments.
    uint256 public stableCollateralTotal;

    /// @notice The maximum funding velocity used to limit the funding rate fluctuations.
    /// @dev Funding velocity is used for calculating the current funding rate and acts as
    ///      a limit on how much the funding rate can change between funding re-computations.
    ///      The units are %/day (1e18 = 100% / day at max or min skew).
    uint256 public maxFundingVelocity;

    /// @notice The skew percentage at which the funding rate velocity is at its maximum.
    /// @dev When absolute pSkew > maxVelocitySkew, then funding velocity = maxFundingVelocity.
    ///      The units are in % (0.1e18 = 10% skew)
    uint256 public maxVelocitySkew;

    /// @notice The minimum time that needs to expire between trade announcement and execution
    uint64 public minExecutabilityAge;

    // Keepers have limited time to execute announced transactions otherwise they will expire
    // and the user has to submit another transaction
    uint64 public maxExecutabilityAge;

    /// @notice Maximum cap on the total stable LP deposits
    uint256 public stableCollateralCap;

    /// @notice The maximum limit of total leverage long size vs stable LP.
    /// @dev This prevents excessive short skew of stable LPs by capping long trader total open interest
    uint256 public skewFractionMax;

    /// @notice Holds mapping between module keys and module addresses.
    ///         A module key is a keccak256 hash of the module name.
    /// @dev NOTE: Make sure that a module key is created using the following format:
    ///            moduleKey = bytes32(<MODULE_NAME>)
    mapping(bytes32 moduleKey => address moduleAddress) public moduleAddress;

    /// @notice Holds mapping between module addresses and their authorization status.
    mapping(address moduleAddress => bool authorized) public isAuthorizedModule;

    /// @dev Tracks global totals of leverage trade positions to be able to price stable LP value
    ///      in real time before the leverage positions are closed.
    FlatcoinStructs.GlobalPositions internal _globalPositions;

    /// @notice Holds mapping between user addresses and their leverage positions.
    mapping(uint256 tokenId => FlatcoinStructs.Position userPosition) internal _positions;

    mapping(bytes32 moduleKey => bool paused) public isModulePaused;

    modifier onlyFlatcoinContracts() {
        if (isAuthorizedModule[msg.sender] == false) revert FlatcoinErrors.OnlyAuthorizedModule(msg.sender);
        _;
    }

    /// @dev To prevent the implementation contract from being used, we invoke the _disableInitializers
    /// function in the constructor to automatically lock it when it is deployed.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Function to initialize this contract.
    function initialize(
        address _owner,
        IERC20Upgradeable _collateral,
        uint256 _maxFundingVelocity,
        uint256 _maxVelocitySkew,
        uint256 _skewFractionMax,
        uint256 _stableCollateralCap,
        uint32 _minExecutabilityAge,
        uint32 _maxExecutabilityAge
    ) external initializer {
        if (address(_collateral) == address(0)) revert FlatcoinErrors.ZeroAddress("collateral");
        __Ownable_init();
        _transferOwnership(_owner);

        collateral = _collateral;

        setMaxFundingVelocity(_maxFundingVelocity);
        setMaxVelocitySkew(_maxVelocitySkew);
        setStableCollateralCap(_stableCollateralCap);
        setSkewFractionMax(_skewFractionMax);
        setExecutabilityAge(_minExecutabilityAge, _maxExecutabilityAge);
    }

    /////////////////////////////////////////////
    //            Module Functions             //
    /////////////////////////////////////////////

    /// @notice Collateral can only be withdrawn by the flatcoin contracts (Delayed Orders, Stable or Leverage module).
    function sendCollateral(address to, uint256 amount) external onlyFlatcoinContracts {
        collateral.safeTransfer(to, amount);
    }

    function updateStableCollateralTotal(int256 _stableCollateralAdjustment) external onlyFlatcoinContracts {
        int256 newStableCollateralTotal = int256(stableCollateralTotal) + _stableCollateralAdjustment;
        // TODO: Explore what should be done in the case newStableCollateralTotal < 0. I think the next line will revert with an underflow error.
        stableCollateralTotal = uint256(newStableCollateralTotal);
    }

    function setPosition(
        FlatcoinStructs.Position calldata _newPosition,
        uint256 _tokenId
    ) external onlyFlatcoinContracts {
        _positions[_tokenId] = _newPosition;
    }

    function deletePosition(uint256 _tokenId) external onlyFlatcoinContracts {
        delete _positions[_tokenId];
    }

    function setGlobalPositions(
        FlatcoinStructs.GlobalPositions calldata _newGlobalPositions
    ) external onlyFlatcoinContracts {
        _globalPositions = _newGlobalPositions;
    }

    function deleteGlobalPositions() external onlyFlatcoinContracts {
        delete _globalPositions;
    }

    function updateGlobalPositionData(
        uint256 price,
        int256 marginDelta,
        int256 additionalSizeDelta
    ) external onlyFlatcoinContracts {
        int256 sizeOpenedTotal = int256(_globalPositions.sizeOpenedTotal);
        int256 marginDepositedTotal = int256(_globalPositions.marginDepositedTotal);
        int256 averageEntryPrice = int256(_globalPositions.averageEntryPrice);

        // Recompute the average entry price.
        if ((sizeOpenedTotal + additionalSizeDelta) != 0) {
            int256 newAveragePrice = ((averageEntryPrice * sizeOpenedTotal) + (int256(price) * additionalSizeDelta)) /
                (sizeOpenedTotal + additionalSizeDelta);

            assert(newAveragePrice >= 0);

            // Update the global average entry price.
            _globalPositions.averageEntryPrice = uint256(newAveragePrice);

            // Update the global margin deposited/left.
            _globalPositions.marginDepositedTotal = uint256(marginDepositedTotal + marginDelta);

            // Update the global size opened.
            _globalPositions.sizeOpenedTotal = uint256(sizeOpenedTotal + additionalSizeDelta);
        } else {
            // Close the last remaining position.
            // TODO: Find a more elegant way to handle rounding errors.
            if ((marginDepositedTotal + marginDelta) > 1e6) revert FlatcoinErrors.MarginMismatchOnClose();

            delete _globalPositions;
        }
    }

    /////////////////////////////////////////////
    //            Public Functions             //
    /////////////////////////////////////////////

    /// @notice Function to settle the funding fees between longs and LPs.
    /// @dev Anyone can call this function to settle the funding fees.
    /// @return fundingFees The funding fees paid to longs.
    ///         If it's negative, longs pay shorts and vice versa.
    function settleFundingFees() public returns (int256 fundingFees) {
        (int256 fundingChangeSinceRecomputed, int256 unrecordedFunding) = _getUnrecordedFunding();

        // Record the funding rate change and update the cumulative funding rate.
        cumulativeFundingRate = PerpMath._nextFundingEntry(unrecordedFunding, cumulativeFundingRate);

        // Update the latest funding rate and the latest funding recomputation timestamp.
        lastRecomputedFundingRate += fundingChangeSinceRecomputed;
        lastRecomputedFundingTimestamp = uint64(block.timestamp);

        // Calculate the funding fees accrued to the longs.
        fundingFees = PerpMath._accruedFundingTotalByLongs(_globalPositions, unrecordedFunding);

        // Adjust the margin and collateral amounts.
        // TODO: Figure out what to do in case marginDepositedTotal < abs(fundingFees) and fundingFees is < 0.
        _globalPositions.marginDepositedTotal = uint256(int256(_globalPositions.marginDepositedTotal) + fundingFees);

        // TODO: Figure out what to do in case stableCollateralTotal < abs(fundingFees) and fundingFees is > 0.
        stableCollateralTotal = uint256(int256(stableCollateralTotal) - fundingFees);
    }

    /////////////////////////////////////////////
    //             View Functions              //
    /////////////////////////////////////////////

    function getVaultSummary() external view returns (FlatcoinStructs.VaultSummary memory vaultSummary) {
        return
            FlatcoinStructs.VaultSummary({
                marketSkew: int256(_globalPositions.sizeOpenedTotal) - int256(stableCollateralTotal),
                cumulativeFundingRate: cumulativeFundingRate,
                lastRecomputedFundingRate: lastRecomputedFundingRate,
                lastRecomputedFundingTimestamp: lastRecomputedFundingTimestamp,
                stableCollateralTotal: stableCollateralTotal,
                globalPositions: _globalPositions
            });
    }

    function getCurrentFundingRate() external view returns (int256 currentFundingRate) {
        return
            PerpMath._currentFundingRate({
                proportionalSkew: PerpMath._proportionalSkew({
                    skew: int256(_globalPositions.sizeOpenedTotal) - int256(stableCollateralTotal),
                    stableCollateralTotal: stableCollateralTotal
                }),
                lastRecomputedFundingRate: lastRecomputedFundingRate,
                lastRecomputedFundingTimestamp: lastRecomputedFundingTimestamp,
                maxFundingVelocity: maxFundingVelocity,
                maxVelocitySkew: maxVelocitySkew
            });
    }

    function getPosition(uint256 _tokenId) external view returns (FlatcoinStructs.Position memory position) {
        return _positions[_tokenId];
    }

    function getGlobalPositions() external view returns (FlatcoinStructs.GlobalPositions memory globalPositions) {
        return _globalPositions;
    }

    function getOwner() external view returns (address ownerAddress) {
        return owner();
    }

    /// @notice Asserts that the system will not be too skewed towards longs after additional skew is added (position change)
    /// @param additionalSkew The additional skew added by either opening a long or closing an LP position
    function checkSkewMax(uint256 additionalSkew) public view {
        // check that skew is not essentially disabled
        if (skewFractionMax < type(uint256).max) {
            uint256 sizeOpenedTotal = _globalPositions.sizeOpenedTotal;

            if (stableCollateralTotal == 0) revert FlatcoinErrors.ZeroValue("stableCollateralTotal");

            uint256 longSkewFraction = ((sizeOpenedTotal + additionalSkew) * 1e18) / stableCollateralTotal;

            if (longSkewFraction > skewFractionMax) revert FlatcoinErrors.MaxSkewReached(longSkewFraction);
        }
    }

    /// @notice Reverts if the stable LP deposit cap is reached on deposit
    function checkCollateralCap(uint256 depositAmount) public view {
        uint256 collateralCap = stableCollateralCap;

        if (stableCollateralTotal + depositAmount > collateralCap)
            revert FlatcoinErrors.DepositCapReached(collateralCap);
    }

    /// @notice Returns the current skew of the market taking into account unnacrued funding.
    function getCurrentSkew() external view returns (int256 skew) {
        (, int256 unrecordedFunding) = _getUnrecordedFunding();
        uint256 sizeOpenedTotal = _globalPositions.sizeOpenedTotal;

        return
            int256(sizeOpenedTotal) -
            int256(stableCollateralTotal) -
            (int256(sizeOpenedTotal) * unrecordedFunding) /
            1e18;
    }

    /////////////////////////////////////////////
    //             Owner Functions             //
    /////////////////////////////////////////////

    /// @notice Setter for the maximum leverage total skew fraction
    /// @dev This ensures that stable LPs are not too short by capping long trader total open interest
    function setSkewFractionMax(uint256 _skewFractionMax) public onlyOwner {
        if (_skewFractionMax < 1e18) revert FlatcoinErrors.InvalidSkewFractionMax(_skewFractionMax);

        skewFractionMax = _skewFractionMax;
    }

    function setCollateral(IERC20Upgradeable _collateral) external onlyOwner {
        collateral = _collateral;
    }

    /// @dev NOTE: `newMaxFundingVelocity` should include 18 decimals.
    function setMaxFundingVelocity(uint256 newMaxFundingVelocity) public onlyOwner {
        settleFundingFees(); // settle funding fees before updating the max funding velocity so that positions are not affected by the change
        maxFundingVelocity = newMaxFundingVelocity;
    }

    /// @dev NOTE: `newMaxVelocitySkew` should include 18 decimals.
    function setMaxVelocitySkew(uint256 _maxVelocitySkew) public onlyOwner {
        if (_maxVelocitySkew > 1e18 || _maxVelocitySkew == 0)
            revert FlatcoinErrors.InvalidMaxVelocitySkew(_maxVelocitySkew);

        settleFundingFees(); // settle funding fees before updating the max velocity skew so that positions are not affected by the change
        maxVelocitySkew = _maxVelocitySkew;
    }

    function addAuthorizedModules(FlatcoinStructs.AuthorizedModule[] calldata modules) external onlyOwner {
        uint8 modulesLength = uint8(modules.length);

        for (uint8 i; i < modulesLength; ++i) {
            addAuthorizedModule(modules[i]);
        }
    }

    /// @notice Function to set an authorized module.
    /// @dev NOTE: This function can overwrite an existing authorized module.
    function addAuthorizedModule(FlatcoinStructs.AuthorizedModule calldata module) public onlyOwner {
        if (module.moduleAddress == address(0)) revert FlatcoinErrors.ZeroAddress("moduleAddress");
        if (module.moduleKey == bytes32(0)) revert FlatcoinErrors.ZeroValue("moduleKey");

        moduleAddress[module.moduleKey] = module.moduleAddress;
        isAuthorizedModule[module.moduleAddress] = true;
    }

    /// @notice Function to remove an authorized module.
    function removeAuthorizedModule(bytes32 modKey) public onlyOwner {
        address modAddress = moduleAddress[modKey];

        delete moduleAddress[modKey];
        delete isAuthorizedModule[modAddress];
    }

    /// @notice Function to pause the module
    /// @dev This function won't make any state changes if already paused.
    function pauseModule(bytes32 moduleKey) external onlyOwner {
        isModulePaused[moduleKey] = true;
    }

    /// @notice Function to unpause the critical functions
    /// @dev This function won't make any state changes if already unpaused.
    function unpauseModule(bytes32 moduleKey) external onlyOwner {
        isModulePaused[moduleKey] = false;
    }

    function setStableCollateralCap(uint256 _collateralCap) public onlyOwner {
        stableCollateralCap = _collateralCap;
    }

    /// @notice Setter for the minimum and maximum time delayed executatibility
    /// @dev The maximum executability timer starts after the minimum time has elapsed
    function setExecutabilityAge(uint64 _minExecutabilityAge, uint64 _maxExecutabilityAge) public onlyOwner {
        if (_minExecutabilityAge == 0) revert FlatcoinErrors.ZeroValue("minExecutabilityAge");
        if (_maxExecutabilityAge == 0) revert FlatcoinErrors.ZeroValue("maxExecutabilityAge");

        minExecutabilityAge = _minExecutabilityAge;
        maxExecutabilityAge = _maxExecutabilityAge;
    }

    /////////////////////////////////////////////
    //            Internal Functions           //
    /////////////////////////////////////////////

    function _getUnrecordedFunding()
        internal
        view
        returns (int256 fundingChangeSinceRecomputed, int256 unrecordedFunding)
    {
        int256 proportionalSkew = PerpMath._proportionalSkew({
            skew: int256(_globalPositions.sizeOpenedTotal) - int256(stableCollateralTotal),
            stableCollateralTotal: stableCollateralTotal
        });

        fundingChangeSinceRecomputed = PerpMath._fundingChangeSinceRecomputed({
            proportionalSkew: proportionalSkew,
            prevFundingModTimestamp: lastRecomputedFundingTimestamp,
            maxFundingVelocity: maxFundingVelocity,
            maxVelocitySkew: maxVelocitySkew
        });

        unrecordedFunding = PerpMath._unrecordedFunding({
            currentFundingRate: fundingChangeSinceRecomputed + lastRecomputedFundingRate,
            prevFundingRate: lastRecomputedFundingRate,
            prevFundingModTimestamp: lastRecomputedFundingTimestamp
        });
    }
}
