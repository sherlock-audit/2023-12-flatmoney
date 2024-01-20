// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {IChainlinkAggregatorV3} from "../interfaces/IChainlinkAggregatorV3.sol";
import {IPyth} from "pyth-sdk-solidity/IPyth.sol";

library FlatcoinStructs {
    /// @notice Global position data
    /// @dev This is the consolidated data of all leverage positions used to calculate funding fees and total profit and loss.
    /// @dev One can imagine this as being the data of a single big position on leverage side against the stable side.
    /// @param marginDepositedTotal Total collateral deposited for leverage trade positions.
    /// @param lastPrice The last time funding fees and profit and loss were settled.
    /// @param sizeOpenedTotal The total size of leverage across all trades on entry.
    struct GlobalPositions {
        uint256 marginDepositedTotal;
        uint256 lastPrice;
        uint256 sizeOpenedTotal;
    }

    /// @notice Individual leverage position
    struct Position {
        uint256 lastPrice;
        uint256 marginDeposited;
        uint256 additionalSize;
        int256 entryCumulativeFunding;
    }

    struct MarketSummary {
        int256 profitLossTotalByLongs;
        int256 accruedFundingTotalByLongs;
        int256 currentFundingRate;
        int256 nextFundingEntry;
    }

    struct PositionSummary {
        int256 profitLoss;
        int256 accruedFunding;
        int256 marginAfterSettlement;
    }

    struct VaultSummary {
        int256 marketSkew;
        int256 cumulativeFundingRate;
        int256 lastRecomputedFundingRate;
        uint64 lastRecomputedFundingTimestamp;
        uint256 stableCollateralTotal;
        GlobalPositions globalPositions;
    }

    enum OrderType {
        None, // 0
        StableDeposit, // 1
        StableWithdraw, // 2
        LeverageOpen, // 3
        LeverageClose, // 4
        LeverageAdjust, // 5
        LimitClose // 6
    }

    struct Order {
        OrderType orderType;
        uint256 keeperFee; // The deposit paid upon submitting that needs to be paid / refunded on tx confirmation
        uint64 executableAtTime; // The timestamp at which this order is executable at
        bytes orderData;
    }

    struct AnnouncedStableDeposit {
        uint256 depositAmount;
        uint256 minAmountOut; // The minimum amount of tokens expected to receive back
    }

    struct AnnouncedStableWithdraw {
        uint256 withdrawAmount;
        uint256 minAmountOut; // The minimum amount of underlying tokens expected to receive back
    }

    struct AnnouncedLeverageOpen {
        uint256 margin; // The margin amount to be used as leverage collateral
        uint256 additionalSize; // The additional size exposure (leverage)
        uint256 maxFillPrice; // The maximum price accepted by the user
        uint256 tradeFee;
    }

    struct AnnouncedLeverageAdjust {
        uint256 tokenId;
        int256 marginAdjustment;
        int256 additionalSizeAdjustment;
        uint256 fillPrice; // should be passed depending on the type of additionalSizeAdjustment
        uint256 tradeFee;
        uint256 totalFee;
    }

    struct LimitClose {
        uint256 tokenId;
        uint256 priceLowerThreshold;
        uint256 priceUpperThreshold;
        uint256 tradeFee;
    }

    struct AnnouncedLeverageClose {
        uint256 tokenId; // The NFT of the position
        uint256 minFillPrice; // The minimum price accepted by the user
        uint256 tradeFee;
    }

    struct OnchainOracle {
        IChainlinkAggregatorV3 oracleContract; // Chainlink oracle contract
        uint32 maxAge; // Oldest price that is acceptable to use
    }

    struct OffchainOracle {
        IPyth oracleContract; // Pyth network oracle contract
        bytes32 priceId; // Pyth network price Id
        uint32 maxAge; // Oldest price that is acceptable to use
        uint32 minConfidenceRatio; // the minimum Pyth oracle price / expo ratio. The higher, the more confident the accuracy of the price.
    }

    struct AuthorizedModule {
        bytes32 moduleKey;
        address moduleAddress;
    }

    struct LeveragePositionData {
        uint256 tokenId;
        uint256 lastPrice;
        uint256 marginDeposited;
        uint256 additionalSize;
        int256 entryCumulativeFunding;
        int256 profitLoss;
        int256 accruedFunding;
        int256 marginAfterSettlement;
        uint256 liquidationPrice;
    }
}
