// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import {FlatcoinErrors} from "../libraries/FlatcoinErrors.sol";
import {FlatcoinModuleKeys} from "../libraries/FlatcoinModuleKeys.sol";

// Interfaces
import {IOracleModule} from "../interfaces/IOracleModule.sol";
import {IGasPriceOracle} from "../interfaces/IGasPriceOracle.sol";
import {IChainlinkAggregatorV3} from "../interfaces/IChainlinkAggregatorV3.sol";

/// @title KeeperFee
/// @notice A dynamic gas fee module to be used on L2s.
/// @dev Adapted from Synthetix PerpsV2DynamicFeesModule.
///      See https://sips.synthetix.io/sips/sip-2013
contract KeeperFee is Ownable {
    using Math for uint256;

    bytes32 public constant MODULE_KEY = FlatcoinModuleKeys._KEEPER_FEE_MODULE_KEY;

    IChainlinkAggregatorV3 private _ethOracle; // ETH price for gas unit conversions
    IGasPriceOracle private _gasPriceOracle = IGasPriceOracle(0x420000000000000000000000000000000000000F); // gas price oracle as deployed on Optimism L2 rollups
    IOracleModule private _oracleModule; // for collateral asset pricing (the flatcoin market)

    uint256 private constant _UNIT = 10 ** 18;
    uint256 private constant _STALENESS_PERIOD = 1 days;

    address private _assetToPayWith;
    uint256 private _profitMarginUSD;
    uint256 private _profitMarginPercent;
    uint256 private _keeperFeeUpperBound;
    uint256 private _keeperFeeLowerBound;
    uint256 private _gasUnitsL1;
    uint256 private _gasUnitsL2;

    constructor(
        address owner,
        address ethOracle,
        address oracleModule,
        address assetToPayWith,
        uint256 profitMarginUSD,
        uint256 profitMarginPercent,
        uint256 keeperFeeUpperBound,
        uint256 keeperFeeLowerBound,
        uint256 gasUnitsL1,
        uint256 gasUnitsL2
    ) {
        // Do not call Ownable constructor which sets the owner to the msg.sender and set it to _owner.
        _transferOwnership(owner);

        // contracts
        _ethOracle = IChainlinkAggregatorV3(ethOracle);
        _oracleModule = IOracleModule(oracleModule);

        // params
        _assetToPayWith = assetToPayWith;
        _profitMarginUSD = profitMarginUSD;
        _profitMarginPercent = profitMarginPercent;
        _keeperFeeUpperBound = keeperFeeUpperBound; // In USD
        _keeperFeeLowerBound = keeperFeeLowerBound; // In USD
        _gasUnitsL1 = gasUnitsL1;
        _gasUnitsL2 = gasUnitsL2;

        // Check that the oracle asset price is valid
        (uint256 assetPrice, uint256 timestamp) = IOracleModule(oracleModule).getPrice();

        if (assetPrice <= 0) revert FlatcoinErrors.PriceInvalid(FlatcoinErrors.PriceSource.OnChain);

        if (block.timestamp >= timestamp + _STALENESS_PERIOD)
            revert FlatcoinErrors.PriceStale(FlatcoinErrors.PriceSource.OnChain);
    }

    /////////////////////////////////////////////
    //             View Functions              //
    /////////////////////////////////////////////

    /// @dev Returns computed gas price given on-chain variables.
    function getKeeperFee() public view returns (uint256 keeperFeeCollateral) {
        uint256 ethPrice18;
        {
            (, int256 ethPrice, , uint256 ethPriceupdatedAt, ) = _ethOracle.latestRoundData();
            if (block.timestamp >= ethPriceupdatedAt + _STALENESS_PERIOD) revert FlatcoinErrors.ETHPriceStale();
            if (ethPrice <= 0) revert FlatcoinErrors.ETHPriceInvalid();
            ethPrice18 = uint256(ethPrice) * 1e10; // from 8 decimals to 18
        }
        // NOTE: Currently the market asset and collateral asset are the same.
        // If this changes in the future, then the following line should fetch the collateral asset, not market asset.
        (uint256 collateralPrice, uint256 timestamp) = _oracleModule.getPrice();

        if (collateralPrice <= 0) revert FlatcoinErrors.PriceInvalid(FlatcoinErrors.PriceSource.OnChain);

        if (block.timestamp >= timestamp + _STALENESS_PERIOD)
            revert FlatcoinErrors.PriceStale(FlatcoinErrors.PriceSource.OnChain);

        uint256 gasPriceL2 = _gasPriceOracle.gasPrice();
        uint256 overhead = _gasPriceOracle.overhead();
        uint256 l1BaseFee = _gasPriceOracle.l1BaseFee();
        uint256 decimals = _gasPriceOracle.decimals();
        uint256 scalar = _gasPriceOracle.scalar();

        uint256 costOfExecutionGrossEth = ((((_gasUnitsL1 + overhead) * l1BaseFee * scalar) / 10 ** decimals) +
            (_gasUnitsL2 * gasPriceL2));
        uint256 costOfExecutionGrossUSD = costOfExecutionGrossEth.mulDiv(ethPrice18, _UNIT); // fee priced in USD

        uint256 maxProfitMargin = _profitMarginUSD.max(costOfExecutionGrossUSD.mulDiv(_profitMarginPercent, _UNIT)); // additional USD profit for the keeper
        uint256 costOfExecutionNet = costOfExecutionGrossUSD + maxProfitMargin; // fee priced in USD

        keeperFeeCollateral = (_keeperFeeUpperBound.min(costOfExecutionNet.max(_keeperFeeLowerBound))).mulDiv(
            _UNIT,
            collateralPrice
        ); // fee priced in collateral
    }

    // @dev Returns the current configurations.
    function getConfig()
        external
        view
        returns (
            address gasPriceOracle,
            uint256 profitMarginUSD,
            uint256 profitMarginPercent,
            uint256 keeperFeeUpperBound,
            uint256 keeperFeeLowerBound,
            uint256 gasUnitsL1,
            uint256 gasUnitsL2
        )
    {
        gasPriceOracle = address(_gasPriceOracle);
        profitMarginUSD = _profitMarginUSD;
        profitMarginPercent = _profitMarginPercent;
        keeperFeeUpperBound = _keeperFeeUpperBound;
        keeperFeeLowerBound = _keeperFeeLowerBound;
        gasUnitsL1 = _gasUnitsL1;
        gasUnitsL2 = _gasUnitsL2;
    }

    /////////////////////////////////////////////
    //             Owner Functions             //
    /////////////////////////////////////////////

    /// @dev Sets params used for gas price computation.
    function setParameters(
        uint256 profitMarginUSD,
        uint256 profitMarginPercent,
        uint256 keeperFeeUpperBound,
        uint256 keeperFeeLowerBound,
        uint256 gasUnitsL1,
        uint256 gasUnitsL2
    ) external onlyOwner {
        _profitMarginUSD = profitMarginUSD;
        _profitMarginPercent = profitMarginPercent;
        _keeperFeeUpperBound = keeperFeeUpperBound;
        _keeperFeeLowerBound = keeperFeeLowerBound;
        _gasUnitsL1 = gasUnitsL1;
        _gasUnitsL2 = gasUnitsL2;
    }

    /// @dev Sets keeper fee upper and lower bounds.
    /// @param keeperFeeUpperBound The upper bound of the keeper fee in USD.
    /// @param keeperFeeLowerBound The lower bound of the keeper fee in USD.
    function setParameters(uint256 keeperFeeUpperBound, uint256 keeperFeeLowerBound) external onlyOwner {
        if (keeperFeeUpperBound <= keeperFeeLowerBound) revert FlatcoinErrors.InvalidFee(keeperFeeLowerBound);
        if (keeperFeeLowerBound == 0) revert FlatcoinErrors.ZeroValue("keeperFeeLowerBound");

        _keeperFeeUpperBound = keeperFeeUpperBound;
        _keeperFeeLowerBound = keeperFeeLowerBound;
    }

    /// @dev Sets a custom gas price oracle. May be needed for some chain deployments.
    function setGasPriceOracle(address gasPriceOracle) external onlyOwner {
        if (address(gasPriceOracle) == address(0)) revert FlatcoinErrors.ZeroAddress("gasPriceOracle");

        _gasPriceOracle = IGasPriceOracle(gasPriceOracle);
    }
}
