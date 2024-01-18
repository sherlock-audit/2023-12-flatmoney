// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {IPyth} from "pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "pyth-sdk-solidity/PythStructs.sol";

import {FlatcoinErrors} from "./libraries/FlatcoinErrors.sol";
import {FlatcoinStructs} from "./libraries/FlatcoinStructs.sol";
import {FlatcoinModuleKeys} from "./libraries/FlatcoinModuleKeys.sol";
import {FlatcoinEvents} from "./libraries/FlatcoinEvents.sol";
import {ModuleUpgradeable} from "./abstracts/ModuleUpgradeable.sol";

import {IFlatcoinVault} from "./interfaces/IFlatcoinVault.sol";
import {IOracleModule} from "./interfaces/IOracleModule.sol";
import {IChainlinkAggregatorV3} from "./interfaces/IChainlinkAggregatorV3.sol";

/// @title Interfaces with onchain and offchain oracles (eg. Chainlink and Pyth network)
/// @notice Can query collateral oracle price
contract OracleModule is IOracleModule, ModuleUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SignedMath for int256;

    address public asset; // Asset to price

    FlatcoinStructs.OnchainOracle public onchainOracle; // Onchain Chainlink oracle

    FlatcoinStructs.OffchainOracle public offchainOracle; // Offchain Pyth network oracle

    // Max difference between onchain and offchain oracle. 1e18 = 100%
    uint256 public maxDiffPercent;

    /// @dev To prevent the implementation contract from being used, we invoke the _disableInitializers
    /// function in the constructor to automatically lock it when it is deployed.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Function to initialize this contract.
    function initialize(
        IFlatcoinVault _vault,
        address _asset, // the asset to price
        FlatcoinStructs.OnchainOracle calldata _onchainOracle,
        FlatcoinStructs.OffchainOracle calldata _offchainOracle,
        uint256 _maxDiffPercent
    ) external initializer {
        __Module_init(FlatcoinModuleKeys._ORACLE_MODULE_KEY, _vault);
        __ReentrancyGuard_init();

        _setAsset(_asset);
        _setOnchainOracle(_onchainOracle);
        _setOffchainOracle(_offchainOracle);
        _setMaxDiffPercent(_maxDiffPercent);
    }

    // TODO: Check if the function should only be updated by trusted contracts or not
    function updatePythPrice(address sender, bytes[] calldata priceUpdateData) external payable nonReentrant {
        // Get fee amount to pay to Pyth
        uint256 fee = offchainOracle.oracleContract.getUpdateFee(priceUpdateData);

        // Update the price data (and pay the fee)
        offchainOracle.oracleContract.updatePriceFeeds{value: fee}(priceUpdateData);

        if (msg.value - fee > 0) {
            // Need to refund caller. Try to return unused value, or revert if failed
            (bool success, ) = sender.call{value: msg.value - fee}("");
            if (success == false) revert FlatcoinErrors.RefundFailed();
        }
    }

    /////////////////////////////////////////////
    //             View Functions              //
    /////////////////////////////////////////////

    /// @notice Returns the latest 18 decimal price of asset from either Pyth.network or Chainlink.
    /// @dev The oldest pricestamp will be the Chainlink oracle `maxAge` setting. Otherwise the call will revert.
    function getPrice() public view returns (uint256 price, uint256 timestamp) {
        (price, timestamp) = _getPrice(type(uint32).max);
    }

    /// @notice The same as getPrice() but it includes maximum acceptable oracle timestamp input parameter
    /// @param maxAge Oldest acceptable oracle price
    function getPrice(uint32 maxAge) public view returns (uint256 price, uint256 timestamp) {
        (price, timestamp) = _getPrice(maxAge);
    }

    /////////////////////////////////////////////
    //             Owner Functions             //
    /////////////////////////////////////////////

    /// @notice Sets the asset and oracles (onchain and offchain)
    /// @dev Changes should be handled with care as it's possible to misconfigure
    function setOracle(
        address _asset,
        FlatcoinStructs.OnchainOracle calldata _onchainOracle,
        FlatcoinStructs.OffchainOracle calldata _offchainOracle
    ) external onlyOwner {
        // Note: It's not possible to check that the oracles match the configured asset
        // and any configuration changes should be handled with care.
        _setAsset(_asset);
        _setOnchainOracle(_onchainOracle);
        _setOffchainOracle(_offchainOracle);
    }

    function setMaxDiffPercent(uint256 _maxDiffPercent) external onlyOwner {
        _setMaxDiffPercent(_maxDiffPercent);
    }

    /////////////////////////////////////////////
    //            Internal Functions           //
    /////////////////////////////////////////////

    /// @notice Returns the latest 18 decimal price of asset from either Pyth.network or Chainlink.
    /// @dev It verifies the Pyth network price against Chainlink price (ensure that it is within a threshold).
    function _getPrice(uint32 maxAge) internal view returns (uint256 price, uint256 timestamp) {
        (uint256 onchainPrice, uint256 onchainTime) = _getOnchainPrice(); // will revert if invalid
        (uint256 offchainPrice, uint256 offchainTime, bool offchainInvalid) = _getOffchainPrice();
        bool offchain;

        uint256 priceDiff = (int256(onchainPrice) - int256(offchainPrice)).abs();
        uint256 diffPercent = (priceDiff * 1e18) / onchainPrice;
        if (diffPercent > maxDiffPercent) revert FlatcoinErrors.PriceMismatch(diffPercent);

        if (offchainInvalid == false) {
            // return the freshest price
            if (offchainTime >= onchainTime) {
                price = offchainPrice;
                timestamp = offchainTime;
                offchain = true;
            } else {
                price = onchainPrice;
                timestamp = onchainTime;
            }
            // console2.log("Offchain price: %s", price);
        } else {
            price = onchainPrice;
            timestamp = onchainTime;
            // console2.log("Onchain price: %s", price);
        }

        // Check that the timestamp is within the required age
        if (maxAge < type(uint32).max && timestamp + maxAge < block.timestamp) {
            revert FlatcoinErrors.PriceStale(
                offchain ? FlatcoinErrors.PriceSource.OffChain : FlatcoinErrors.PriceSource.OnChain
            );
        }
    }

    /// @dev Will revert on any issue. This is because the Onchain price is critical
    function _getOnchainPrice() internal view returns (uint256 price, uint256 timestamp) {
        IChainlinkAggregatorV3 oracle = onchainOracle.oracleContract;
        if (address(oracle) == address(0)) revert FlatcoinErrors.ZeroAddress("oracle");

        (, int256 _price, , uint256 updatedAt, ) = oracle.latestRoundData();
        timestamp = updatedAt;
        // check Chainlink oracle price updated within `maxAge` time.
        if (block.timestamp > timestamp + onchainOracle.maxAge)
            revert FlatcoinErrors.PriceStale(FlatcoinErrors.PriceSource.OnChain);

        if (_price > 0) {
            price = uint256(_price) * (10 ** 10); // convert Chainlink oracle decimals 8 -> 18
        } else {
            // Issue with onchain oracle indicates a serious problem
            revert FlatcoinErrors.PriceInvalid(FlatcoinErrors.PriceSource.OnChain);
        }
    }

    /// @dev Will NOT revert on any issue. `_getPrice` can fall back to the Onchain oracle.
    function _getOffchainPrice() internal view returns (uint256 price, uint256 timestamp, bool invalid) {
        IPyth oracle = offchainOracle.oracleContract;
        if (address(oracle) == address(0)) revert FlatcoinErrors.ZeroAddress("oracle");

        try oracle.getPriceNoOlderThan(offchainOracle.priceId, offchainOracle.maxAge) returns (
            PythStructs.Price memory priceData
        ) {
            timestamp = priceData.publishTime;

            // Check that Pyth price and confidence is a positive value
            // Check that the exponential param is negative (eg -8 for 8 decimals)
            if (priceData.price > 0 && priceData.conf > 0 && priceData.expo < 0) {
                // console2.log("Offchain price in priceData: %s", priceData.price);

                price = uint256(uint64(priceData.price)) * (10 ** uint256(uint32(18 + priceData.expo))); // convert oracle expo/decimals eg 8 -> 18

                // Check that Pyth price confidence meets minimum
                if (priceData.price / int64(priceData.conf) < int32(offchainOracle.minConfidenceRatio)) {
                    invalid = true; // price confidence is too low
                }
            } else {
                invalid = true;
            }
        } catch {
            invalid = true; // couldn't fetch the price with the asked input param
        }
    }

    function _setAsset(address _asset) internal {
        if (_asset == address(0)) revert FlatcoinErrors.ZeroAddress("asset");

        asset = _asset;
        emit FlatcoinEvents.SetAsset(_asset);
    }

    /// @notice Setting a Chainlink price feed push oracle
    /// @param newOracle The Chainlink aggregator oracle address
    function _setOnchainOracle(FlatcoinStructs.OnchainOracle calldata newOracle) internal {
        if (address(newOracle.oracleContract) == address(0) || newOracle.maxAge <= 0)
            revert FlatcoinErrors.OracleConfigInvalid();

        onchainOracle = newOracle;
        emit FlatcoinEvents.SetOnChainOracle(newOracle);
    }

    /// @notice Setting a Pyth Network price feed pull oracle
    /// @param newOracle The new onchain oracle configuration
    function _setOffchainOracle(FlatcoinStructs.OffchainOracle calldata newOracle) internal {
        if (
            address(newOracle.oracleContract) == address(0) ||
            newOracle.priceId == bytes32(0) ||
            newOracle.maxAge <= 0 ||
            newOracle.minConfidenceRatio <= 0
        ) revert FlatcoinErrors.OracleConfigInvalid();

        offchainOracle = FlatcoinStructs.OffchainOracle(
            newOracle.oracleContract,
            newOracle.priceId,
            newOracle.maxAge,
            newOracle.minConfidenceRatio
        );
        emit FlatcoinEvents.SetOffChainOracle(newOracle);
    }

    /// @notice Setting the maximum percentage between onchain and offchain oracle
    function _setMaxDiffPercent(uint256 _maxDiffPercent) internal {
        if (_maxDiffPercent < 0.005e18 || _maxDiffPercent > 1e18) revert FlatcoinErrors.OracleConfigInvalid();
        maxDiffPercent = _maxDiffPercent;

        emit FlatcoinEvents.SetMaxDiffPercent(_maxDiffPercent);
    }
}
