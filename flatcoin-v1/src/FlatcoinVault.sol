// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {SafeCastUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/math/SafeCastUpgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";

import {FlatcoinErrors} from "./libraries/FlatcoinErrors.sol";
import {FlatcoinStructs} from "./libraries/FlatcoinStructs.sol";
import {PerpMath} from "./libraries/PerpMath.sol";

import {IFlatcoinVault} from "./interfaces/IFlatcoinVault.sol";

/// @title FlatcoinVault
/// @author dHEDGE
/// @notice Contains state to be reused by different modules of the system.
/// @dev Holds the stable LP deposits and leverage traders' collateral amounts.
///      Also stores other related contract address pointers.
contract FlatcoinVault is IFlatcoinVault, OwnableUpgradeable {
    using SafeCastUpgradeable for *;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice The collateral token address.
    IERC20Upgradeable public collateral;

    /// @notice The last market skew recomputation timestamp.
    uint64 public lastRecomputedFundingTimestamp;

    /// @notice The minimum time that needs to expire between trade announcement and execution.
    uint64 public minExecutabilityAge;

    /// @notice The maximum amount of time that can expire between trade announcement and execution.
    uint64 public maxExecutabilityAge;

    /// @notice The last recomputed funding rate.
    int256 public lastRecomputedFundingRate;

    /// @notice Sum of funding rate over the entire lifetime of the market.
    int256 public cumulativeFundingRate;

    /// @notice Total collateral deposited by users minting the flatcoin.
    /// @dev This value is adjusted due to funding fee payments.
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

    /// @notice Maximum cap on the total stable LP deposits.
    uint256 public stableCollateralCap;

    /// @notice The maximum limit of total leverage long size vs stable LP.
    /// @dev This prevents excessive short skew of stable LPs by capping long trader total open interest.
    ///      Care needs to be taken when increasing this value as it can lead to the stable LPs being excessively short.
    uint256 public skewFractionMax;

    /// @notice Holds mapping between module keys and module addresses.
    ///         A module key is a keccak256 hash of the module name.
    /// @dev Make sure that a module key is created using the following format:
    ///      moduleKey = bytes32(<MODULE_NAME>)
    ///      All the module keys should reside in a single file (see FlatcoinModuleKeys.sol).
    mapping(bytes32 moduleKey => address moduleAddress) public moduleAddress;

    /// @notice Holds mapping between module addresses and their authorization status.
    mapping(address moduleAddress => bool authorized) public isAuthorizedModule;

    /// @notice Holds mapping between module keys and their pause status.
    mapping(bytes32 moduleKey => bool paused) public isModulePaused;

    /// @dev Tracks global totals of leverage trade positions to be able to:
    ///      - price stable LP value.
    ///      - calculate the funding rate.
    ///      - calculate the skew.
    ///      - calculate funding fees payments.
    FlatcoinStructs.GlobalPositions internal _globalPositions;

    /// @dev Holds mapping between user addresses and their leverage positions.
    mapping(uint256 tokenId => FlatcoinStructs.Position userPosition) internal _positions;

    modifier onlyAuthorizedModule() {
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
    /// @param _owner The owner of this contract.
    /// @param _collateral The collateral token address.
    /// @param _maxFundingVelocity The maximum funding velocity used to limit the funding rate fluctuations.
    /// @param _maxVelocitySkew The skew percentage at which the funding rate velocity is at its maximum.
    /// @param _skewFractionMax The maximum limit of total leverage long size vs stable LP.
    /// @param _stableCollateralCap The maximum cap on the total stable LP deposits.
    /// @param _minExecutabilityAge The minimum time that needs to expire between trade announcement and execution.
    /// @param _maxExecutabilityAge The maximum amount of time that can expire between trade announcement and execution.
    function initialize(
        address _owner,
        IERC20Upgradeable _collateral,
        uint256 _maxFundingVelocity,
        uint256 _maxVelocitySkew,
        uint256 _skewFractionMax,
        uint256 _stableCollateralCap,
        uint64 _minExecutabilityAge,
        uint64 _maxExecutabilityAge
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
    function sendCollateral(address to, uint256 amount) external onlyAuthorizedModule {
        collateral.safeTransfer(to, amount);
    }

    /// @notice Function to set the position of a leverage trader.
    /// @dev This function is only callable by the authorized modules.
    /// @param _newPosition The new struct encoded position of the leverage trader.
    /// @param _tokenId The token ID of the leverage trader.
    function setPosition(
        FlatcoinStructs.Position calldata _newPosition,
        uint256 _tokenId
    ) external onlyAuthorizedModule {
        _positions[_tokenId] = _newPosition;
    }

    /// @notice Function to delete the position of a leverage trader.
    /// @dev This function is only callable by the authorized modules.
    /// @param _tokenId The token ID of the leverage trader.
    function deletePosition(uint256 _tokenId) external onlyAuthorizedModule {
        delete _positions[_tokenId];
    }

    /// @notice Function to update the stable collateral total.
    /// @dev This function is only callable by the authorized modules.
    ///      When `_stableCollateralAdjustment` is negative, it means that the stable collateral total is decreasing.
    /// @param _stableCollateralAdjustment The adjustment to the stable collateral total.
    function updateStableCollateralTotal(int256 _stableCollateralAdjustment) external onlyAuthorizedModule {
        _updateStableCollateralTotal(_stableCollateralAdjustment);
    }

    /// @notice Function to update the global position data.
    /// @dev This function is only callable by the authorized modules.
    /// @param _price The current price of the underlying asset.
    /// @param _marginDelta The change in the margin deposited total.
    /// @param _additionalSizeDelta The change in the size opened total.
    function updateGlobalPositionData(
        uint256 _price,
        int256 _marginDelta,
        int256 _additionalSizeDelta
    ) external onlyAuthorizedModule {
        // Get the total profit loss and update the margin deposited total.
        int256 profitLossTotal = PerpMath._profitLossTotal({globalPosition: _globalPositions, price: _price});

        // Note that technically, even the funding fees should be accounted for when computing the margin deposited total.
        // However, since the funding fees are settled at the same time as the global position data is updated,
        // we can ignore the funding fees here.
        int256 newMarginDepositedTotal = int256(_globalPositions.marginDepositedTotal) + _marginDelta + profitLossTotal;

        // Check that the sum of margin of all the leverage traders is not negative.
        // Rounding errors shouldn't result in a negative margin deposited total given that
        // we are rounding down the profit loss of the position.
        // If anything, after closing the last position in the system, the `marginDepositedTotal` should can be positive.
        // The margin may be negative if liquidations are not happening in a timely manner.
        if (newMarginDepositedTotal < 0) {
            revert FlatcoinErrors.InsufficientGlobalMargin();
        }

        _globalPositions = FlatcoinStructs.GlobalPositions({
            marginDepositedTotal: uint256(newMarginDepositedTotal),
            sizeOpenedTotal: (int256(_globalPositions.sizeOpenedTotal) + _additionalSizeDelta).toUint256(),
            lastPrice: _price
        });

        // Profit loss of leverage traders has to be accounted for by adjusting the stable collateral total.
        // Note that technically, even the funding fees should be accounted for when computing the stable collateral total.
        // However, since the funding fees are settled at the same time as the global position data is updated,
        // we can ignore the funding fees here
        _updateStableCollateralTotal(-profitLossTotal);
    }

    /////////////////////////////////////////////
    //            Public Functions             //
    /////////////////////////////////////////////

    /// @notice Function to settle the funding fees between longs and LPs.
    /// @dev Anyone can call this function to settle the funding fees.
    /// @return _fundingFees The funding fees paid to longs.
    ///         If it's negative, longs pay shorts and vice versa.
    function settleFundingFees() public returns (int256 _fundingFees) {
        (int256 fundingChangeSinceRecomputed, int256 unrecordedFunding) = _getUnrecordedFunding();

        // Record the funding rate change and update the cumulative funding rate.
        cumulativeFundingRate = PerpMath._nextFundingEntry(unrecordedFunding, cumulativeFundingRate);

        // Update the latest funding rate and the latest funding recomputation timestamp.
        lastRecomputedFundingRate += fundingChangeSinceRecomputed;
        lastRecomputedFundingTimestamp = (block.timestamp).toUint64();

        // Calculate the funding fees accrued to the longs.
        // This will be used to adjust the global margin and collateral amounts.
        _fundingFees = PerpMath._accruedFundingTotalByLongs(_globalPositions, unrecordedFunding);

        // In the worst case scenario that the last position which remained open is underwater,
        // we set the margin deposited total to 0. We don't want to have a negative margin deposited total.
        _globalPositions.marginDepositedTotal = (int256(_globalPositions.marginDepositedTotal) > _fundingFees)
            ? uint256(int256(_globalPositions.marginDepositedTotal) + _fundingFees)
            : 0;

        _updateStableCollateralTotal(-_fundingFees);
    }

    /////////////////////////////////////////////
    //             View Functions              //
    /////////////////////////////////////////////

    /// @notice Function to get a summary of the vault.
    /// @dev This can be used by modules to get the current state of the vault.
    /// @return _vaultSummary The vault summary struct.
    function getVaultSummary() external view returns (FlatcoinStructs.VaultSummary memory _vaultSummary) {
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

    /// @notice Function to get the current funding rate.
    /// @dev This can be used by modules to get the current funding rate.
    /// @return currentFundingRate_ The current funding rate.
    function getCurrentFundingRate() external view returns (int256 currentFundingRate_) {
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

    /// @notice Function to get the position details of associated with a `_tokenId`.
    /// @dev This can be used by modules to get the position details of a leverage trader.
    /// @param _tokenId The token ID of the leverage trader.
    /// @return _positionDetails The position struct with details.
    function getPosition(uint256 _tokenId) external view returns (FlatcoinStructs.Position memory _positionDetails) {
        return _positions[_tokenId];
    }

    /// @notice Function to get the global position details.
    /// @dev This can be used by modules to get the global position details.
    /// @return _globalPositionsDetails The global position struct with details.
    function getGlobalPositions()
        external
        view
        returns (FlatcoinStructs.GlobalPositions memory _globalPositionsDetails)
    {
        return _globalPositions;
    }

    /// @notice Asserts that the system will not be too skewed towards longs after additional skew is added (position change).
    /// @param _additionalSkew The additional skew added by either opening a long or closing an LP position.
    function checkSkewMax(uint256 _additionalSkew) public view {
        // check that skew is not essentially disabled
        if (skewFractionMax < type(uint256).max) {
            uint256 sizeOpenedTotal = _globalPositions.sizeOpenedTotal;

            if (stableCollateralTotal == 0) revert FlatcoinErrors.ZeroValue("stableCollateralTotal");

            uint256 longSkewFraction = ((sizeOpenedTotal + _additionalSkew) * 1e18) / stableCollateralTotal;

            if (longSkewFraction > skewFractionMax) revert FlatcoinErrors.MaxSkewReached(longSkewFraction);
        }
    }

    /// @notice Reverts if the stable LP deposit cap is reached on deposit.
    /// @param _depositAmount The amount of stable LP tokens to deposit.
    function checkCollateralCap(uint256 _depositAmount) public view {
        uint256 collateralCap = stableCollateralCap;

        if (stableCollateralTotal + _depositAmount > collateralCap)
            revert FlatcoinErrors.DepositCapReached(collateralCap);
    }

    /// @notice Returns the current skew of the market taking into account unnacrued funding.
    /// @return _skew The current skew of the market.
    function getCurrentSkew() external view returns (int256 _skew) {
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

    /// @notice Setter for the maximum leverage total skew fraction.
    /// @dev This ensures that stable LPs are not too short by capping long trader total open interest.
    ///      Note that `_skewFractionMax` should include 18 decimals.
    /// @param _skewFractionMax The maximum limit of total leverage long size vs stable LP.
    function setSkewFractionMax(uint256 _skewFractionMax) public onlyOwner {
        if (_skewFractionMax < 1e18) revert FlatcoinErrors.InvalidSkewFractionMax(_skewFractionMax);

        skewFractionMax = _skewFractionMax;
    }

    /// @notice Setter for the maximum funding velocity.
    /// @param _newMaxFundingVelocity The maximum funding velocity used to limit the funding rate fluctuations.
    /// @dev NOTE: `_newMaxFundingVelocity` should include 18 decimals.
    function setMaxFundingVelocity(uint256 _newMaxFundingVelocity) public onlyOwner {
        settleFundingFees(); // settle funding fees before updating the max funding velocity so that positions are not affected by the change
        maxFundingVelocity = _newMaxFundingVelocity;
    }

    /// @notice Setter for the maximum funding velocity skew.
    /// @param _newMaxVelocitySkew The skew percentage at which the funding rate velocity is at its maximum.
    /// @dev NOTE: `_newMaxVelocitySkew` should include 18 decimals.
    function setMaxVelocitySkew(uint256 _newMaxVelocitySkew) public onlyOwner {
        if (_newMaxVelocitySkew > 1e18 || _newMaxVelocitySkew == 0)
            revert FlatcoinErrors.InvalidMaxVelocitySkew(_newMaxVelocitySkew);

        settleFundingFees(); // settle funding fees before updating the max velocity skew so that positions are not affected by the change
        maxVelocitySkew = _newMaxVelocitySkew;
    }

    /// @notice Function to add multiple authorized modules.
    /// @dev NOTE: This function can overwrite an existing authorized module.
    /// @param _modules The array of authorized modules to add.
    function addAuthorizedModules(FlatcoinStructs.AuthorizedModule[] calldata _modules) external onlyOwner {
        uint8 modulesLength = uint8(_modules.length);

        for (uint8 i; i < modulesLength; ++i) {
            addAuthorizedModule(_modules[i]);
        }
    }

    /// @notice Function to set an authorized module.
    /// @dev NOTE: This function can overwrite an existing authorized module.
    /// @param _module The authorized module to add.
    function addAuthorizedModule(FlatcoinStructs.AuthorizedModule calldata _module) public onlyOwner {
        if (_module.moduleAddress == address(0)) revert FlatcoinErrors.ZeroAddress("moduleAddress");
        if (_module.moduleKey == bytes32(0)) revert FlatcoinErrors.ZeroValue("moduleKey");

        moduleAddress[_module.moduleKey] = _module.moduleAddress;
        isAuthorizedModule[_module.moduleAddress] = true;
    }

    /// @notice Function to remove an authorized module.
    /// @param _modKey The module key of the module to remove.
    function removeAuthorizedModule(bytes32 _modKey) public onlyOwner {
        address modAddress = moduleAddress[_modKey];

        delete moduleAddress[_modKey];
        delete isAuthorizedModule[modAddress];
    }

    /// @notice Function to pause the module
    /// @param _moduleKey The module key of the module to pause.
    function pauseModule(bytes32 _moduleKey) external onlyOwner {
        isModulePaused[_moduleKey] = true;
    }

    /// @notice Function to unpause the critical functions
    /// @param _moduleKey The module key of the module to unpause.
    function unpauseModule(bytes32 _moduleKey) external onlyOwner {
        isModulePaused[_moduleKey] = false;
    }

    /// @notice Setter for the stable collateral cap.
    /// @param _collateralCap The maximum cap on the total stable LP deposits.
    function setStableCollateralCap(uint256 _collateralCap) public onlyOwner {
        stableCollateralCap = _collateralCap;
    }

    /// @notice Setter for the minimum and maximum time delayed executatibility
    /// @dev The maximum executability timer starts after the minimum time has elapsed
    /// @param _minExecutabilityAge The minimum time that needs to expire between trade announcement and execution.
    /// @param _maxExecutabilityAge The maximum amount of time that can expire between trade announcement and execution.
    function setExecutabilityAge(uint64 _minExecutabilityAge, uint64 _maxExecutabilityAge) public onlyOwner {
        if (_minExecutabilityAge == 0) revert FlatcoinErrors.ZeroValue("minExecutabilityAge");
        if (_maxExecutabilityAge == 0) revert FlatcoinErrors.ZeroValue("maxExecutabilityAge");

        minExecutabilityAge = _minExecutabilityAge;
        maxExecutabilityAge = _maxExecutabilityAge;
    }

    /////////////////////////////////////////////
    //             Private Functions           //
    /////////////////////////////////////////////

    function _updateStableCollateralTotal(int256 _stableCollateralAdjustment) private {
        int256 newStableCollateralTotal = int256(stableCollateralTotal) + _stableCollateralAdjustment;

        // The stable collateral shouldn't be negative as the other calculations which depend on this
        // will behave in unexpected manners.
        stableCollateralTotal = (newStableCollateralTotal > 0) ? uint256(newStableCollateralTotal) : 0;
    }

    /// @dev Function to calculate the unrecorded funding amount.
    function _getUnrecordedFunding()
        private
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
