// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {DecimalMath} from "../libraries/DecimalMath.sol";
import {FlatcoinStructs} from "../libraries/FlatcoinStructs.sol";

/// @title PerpMath
/// @author dHEDGE
/// @notice Abstract contract which contains necessary math functions for perps.
/// @dev Adapted from Synthetix PerpsV2MarketBase <https://github.com/Synthetixio/synthetix/blob/cbd8666f4331ee95fcc667ec7345d13c8ba77efb/contracts/PerpsV2MarketBase.sol#L156>
///      and <https://github.com/Synthetixio/synthetix/blob/cbd8666f4331ee95fcc667ec7345d13c8ba77efb/contracts/SafeDecimalMath.sol>
// TODO: Explore if we can use fixed point library of Solmate.
// solhint-disable named-return-values
library PerpMath {
    using SignedMath for int256;
    using DecimalMath for int256;
    using DecimalMath for uint256;

    /********************************************
     *             State Variables              *
     ********************************************/
    // NOTE: The following variables need to include 18 decimals to aid in FixedPointMath.

    /// @dev Returns the pSkew = skew / skewScale capping the pSkew between [-1, 1].
    /// @param skew The current system skew.
    function _proportionalSkew(int256 skew, uint256 stableCollateralTotal) internal pure returns (int256 pSkew) {
        if (stableCollateralTotal > 0) {
            pSkew = skew._divideDecimal(int256(stableCollateralTotal));

            if (pSkew < -1e18 || pSkew > 1e18) {
                // Note: If the `skewFractionMax` is < 100% then this should never happen
                pSkew = DecimalMath.UNIT.min(pSkew.max(-DecimalMath.UNIT));
            }
        } else {
            assert(skew == 0);
            pSkew = 0;
        }
    }

    /// @dev The funding velocity is based on the market skew and is scaled by the maxVelocitySkew.
    ///      With higher skews beyond the maxVelocitySkew, the velocity remains constant.
    function _currentFundingVelocity(
        int256 proportionalSkew,
        uint256 maxFundingVelocity,
        uint256 maxVelocitySkew
    ) internal pure returns (int256) {
        if (maxVelocitySkew > 0) {
            // Scale the funding velocity by the maxVelocitySkew and cap it at the maximum +- velocity.
            int256 fundingVelocity = (proportionalSkew * int256(maxFundingVelocity)) / int256(maxVelocitySkew);
            return int256(maxFundingVelocity).min(fundingVelocity.max(-int256(maxFundingVelocity)));
        }
        return proportionalSkew._multiplyDecimal(int256(maxFundingVelocity));
    }

    function _proportionalElapsedTime(uint256 prevModTimestamp) internal view returns (uint256) {
        return (block.timestamp - prevModTimestamp)._divideDecimal(1 days);
    }

    function _currentFundingRate(
        int256 lastRecomputedFundingRate,
        uint64 lastRecomputedFundingTimestamp,
        int256 proportionalSkew,
        uint256 maxFundingVelocity,
        uint256 maxVelocitySkew
    ) internal view returns (int256) {
        return
            lastRecomputedFundingRate +
            _fundingChangeSinceRecomputed(
                proportionalSkew,
                lastRecomputedFundingTimestamp,
                maxFundingVelocity,
                maxVelocitySkew
            );
    }

    /// @dev Retrieves the change in funding rate since the last re-computation.
    ///
    /// This is used during funding computation _before_ the market is modified (e.g. closing or
    /// opening a position).
    ///
    /// There is no variance in computation but will be affected based on outside modifications to
    /// the market skew, max funding velocity, and time delta.
    function _fundingChangeSinceRecomputed(
        int256 proportionalSkew,
        uint256 prevFundingModTimestamp,
        uint256 maxFundingVelocity,
        uint256 maxVelocitySkew
    ) internal view returns (int256) {
        // calculations:
        //  - velocity          = proportional_skew * max_funding_velocity
        //  - proportional_skew = skew / stable_collateral_total
        //
        // example:
        //  - time_delta                = 29,000s
        //  - max_funding_velocity      = 0.025 (2.5%)
        //  - skew                      = 200
        //  - stable_collateral_total   = 1000
        //
        //
        // funding_change   = velocity * (time_delta / seconds_in_day)
        // funding_change   = (200 / 1000 * 0.025) * (29,000 / 86,400)
        //                  = 0.005 * 0.33564815
        //                  = 0.00167824075
        return
            _currentFundingVelocity(proportionalSkew, maxFundingVelocity, maxVelocitySkew)._multiplyDecimal(
                int256(_proportionalElapsedTime(prevFundingModTimestamp))
            );
    }

    function _unrecordedFunding(
        FlatcoinStructs.VaultSummary memory vaultSummary,
        uint256 maxFundingVelocity,
        uint256 maxVelocitySkew
    ) internal view returns (int256) {
        int256 nextFundingRate = _currentFundingRate({
            proportionalSkew: _proportionalSkew(vaultSummary.marketSkew, vaultSummary.stableCollateralTotal),
            lastRecomputedFundingRate: vaultSummary.lastRecomputedFundingRate,
            lastRecomputedFundingTimestamp: vaultSummary.lastRecomputedFundingTimestamp,
            maxFundingVelocity: maxFundingVelocity,
            maxVelocitySkew: maxVelocitySkew
        });

        // NOTE: Synthetix uses the -ve sign here. We won't use it here as we believe it makes intutive sense
        // to use the same sign as the skew to preserve the traditional sense of the sign of the funding rate.
        // However, this also means that we have to invert the sign when calculating the difference between user's index
        // and the current global index for accumulated funding rate.
        int256 avgFundingRate = (vaultSummary.lastRecomputedFundingRate + nextFundingRate) / 2;
        return
            avgFundingRate._multiplyDecimal(
                int256(_proportionalElapsedTime(vaultSummary.lastRecomputedFundingTimestamp))
            );
    }

    /// @dev Same as _unrecordedFunding but with the current funding rate passed in.
    function _unrecordedFunding(
        int256 currentFundingRate,
        int256 prevFundingRate,
        uint256 prevFundingModTimestamp
    ) internal view returns (int256) {
        int256 avgFundingRate = (prevFundingRate + currentFundingRate) / 2;
        return avgFundingRate._multiplyDecimal(int256(_proportionalElapsedTime(prevFundingModTimestamp)));
    }

    /**
     * The new entry in the funding sequence, appended when funding is recomputed. It is the sum of the
     * last entry and the unrecorded funding, so the sequence accumulates running total over the market's lifetime.
     */
    function _nextFundingEntry(
        FlatcoinStructs.VaultSummary memory vaultSummary,
        uint256 maxFundingVelocity,
        uint256 maxVelocitySkew
    ) internal view returns (int256) {
        return
            vaultSummary.cumulativeFundingRate + _unrecordedFunding(vaultSummary, maxFundingVelocity, maxVelocitySkew);
    }

    function _nextFundingEntry(
        int256 unrecordedFunding,
        int256 latestFundingSequenceEntry
    ) internal pure returns (int256) {
        return latestFundingSequenceEntry + unrecordedFunding;
    }

    /// @dev Same as _netFundingPerUnit but with the next funding entry passed in.
    function _netFundingPerUnit(
        int256 userFundingSequenceEntry,
        int256 nextFundingEntry
    ) internal pure returns (int256) {
        return userFundingSequenceEntry - nextFundingEntry;
    }

    /*******************************************
     *             Position Details             *
     *******************************************/

    /// Determines whether a change in a position's size would violate the max market value constraint.
    // TODO: Determine the signs of the variables used in this function.
    // DOUBT: How do we determine if order size is too large?
    // function _orderSizeTooLarge(
    //     int256 skew,
    //     int256 oldSize,
    //     int256 newSize,
    //     uint256 maxSize
    // ) internal view returns (bool) {
    //     // Allow users to reduce an order no matter the market conditions.
    //     if (_sameSide(oldSize, newSize) && newSize.abs() <= oldSize.abs()) {
    //         return false;
    //     }

    //     // Either the user is flipping sides, or they are increasing an order on the same side they're already on;
    //     // we check that the side of the market their order is on would not break the limit.
    //     int256 newSkew = skew - oldSize + newSize;
    //     int newMarketSize = int(marketState.marketSize()).sub(_signedAbs(oldSize)).add(_signedAbs(newSize));

    //     int newSideSize;
    //     if (0 < newSize) {
    //         // DOUBT: Why is `newSkew` != `longSize` - `shortSize`? Is it because `shortSize` is actually -ve?
    //         // long case: marketSize + skew
    //         //            = (|longSize| + |shortSize|) + (longSize + shortSize)
    //         //            = 2 * longSize
    //         newSideSize = newMarketSize.add(newSkew);
    //     } else {
    //         // short case: marketSize - skew
    //         //            = (|longSize| + |shortSize|) - (longSize + shortSize)
    //         //            = 2 * -shortSize
    //         newSideSize = newMarketSize.sub(newSkew);
    //     }

    //     // newSideSize still includes an extra factor of 2 here, so we will divide by 2 in the actual condition
    //     if (maxSize < _abs(newSideSize.div(2))) {
    //         return true;
    //     }

    //     return false;
    // }

    /// @dev Note: `price` uses 18 decimals.
    function _notionalValue(int256 positionSize, uint256 price) internal pure returns (int256 value) {
        return positionSize._multiplyDecimal(int256(price));
    }

    /// @dev NOTE: Returns the PnL in terms of the market currency (ETH/stETH) and not in dollars ($).
    function _profitLoss(FlatcoinStructs.Position memory position, uint256 price) internal pure returns (int256 pnl) {
        int256 priceShift = int256(price) - int256(position.entryPrice);

        return (int256(position.additionalSize) * (priceShift)) / int256(price);
    }

    /// @dev NOTE: Returns the PnL in terms of the market currency (ETH/stETH) and not in dollars ($).
    function _profitLossTotal(
        FlatcoinStructs.GlobalPositions memory globalPosition,
        uint256 price
    ) internal pure returns (int256 pnl) {
        int256 priceShift = int256(price) - int256(globalPosition.averageEntryPrice);

        return (int256(globalPosition.sizeOpenedTotal) * (priceShift)) / int256(price);
    }

    function _accruedFunding(
        FlatcoinStructs.Position memory position,
        int256 nextFundingEntry
    ) internal pure returns (int256) {
        int256 net = _netFundingPerUnit(position.entryCumulativeFunding, nextFundingEntry);

        return int256(position.additionalSize)._multiplyDecimal(net);
    }

    /// @dev Same as `_accruedFundingTotalByLongs` but with unrecorded funding passed in.
    function _accruedFundingTotalByLongs(
        FlatcoinStructs.GlobalPositions memory globalPosition,
        int256 unrecordedFunding
    ) internal pure returns (int256) {
        return -int256(globalPosition.sizeOpenedTotal)._multiplyDecimal(unrecordedFunding);
    }

    /// @dev Same as `_marginPlusProfitFunding` but with the next funding entry passed in.
    function _marginPlusProfitFunding(
        FlatcoinStructs.Position memory position,
        int256 nextFundingEntry,
        uint256 price
    ) internal pure returns (int256) {
        return
            int256(position.marginDeposited) +
            _profitLoss(position, price) +
            _accruedFunding(position, nextFundingEntry);
    }

    function _getPositionSummary(
        FlatcoinStructs.Position memory position,
        int256 nextFundingEntry,
        uint256 price
    ) internal pure returns (FlatcoinStructs.PositionSummary memory) {
        int256 profitLoss = _profitLoss(position, price);
        int256 accruedFunding = _accruedFunding(position, nextFundingEntry);

        return
            FlatcoinStructs.PositionSummary({
                profitLoss: profitLoss,
                accruedFunding: accruedFunding,
                marginAfterSettlement: int256(position.marginDeposited) + profitLoss + accruedFunding
            });
    }

    function _getMarketSummaryLongs(
        FlatcoinStructs.VaultSummary memory vaultSummary,
        uint256 maxFundingVelocity,
        uint256 maxVelocitySkew,
        uint256 price
    ) internal view returns (FlatcoinStructs.MarketSummary memory) {
        int256 currentFundingRate = _currentFundingRate({
            proportionalSkew: _proportionalSkew(vaultSummary.marketSkew, vaultSummary.stableCollateralTotal),
            lastRecomputedFundingRate: vaultSummary.lastRecomputedFundingRate,
            lastRecomputedFundingTimestamp: vaultSummary.lastRecomputedFundingTimestamp,
            maxFundingVelocity: maxFundingVelocity,
            maxVelocitySkew: maxVelocitySkew
        });
        int256 unrecordedFunding = _unrecordedFunding(
            currentFundingRate,
            vaultSummary.lastRecomputedFundingRate,
            vaultSummary.lastRecomputedFundingTimestamp
        );

        return
            FlatcoinStructs.MarketSummary({
                profitLossTotalByLongs: _profitLossTotal(vaultSummary.globalPositions, price),
                accruedFundingTotalByLongs: _accruedFundingTotalByLongs(
                    vaultSummary.globalPositions,
                    unrecordedFunding
                ),
                currentFundingRate: currentFundingRate,
                nextFundingEntry: _nextFundingEntry(unrecordedFunding, vaultSummary.cumulativeFundingRate)
            });
    }

    /********************************************
     *            Liquidation Methods           *
     ********************************************/

    /// @notice Function to calculate the approximate liquidation price.
    /// @dev Only approximation can be achieved due to the fact that the funding rate influences the liquidation price.
    /// @param position The position to calculate the liquidation price for.
    /// @param nextFundingEntry The next (recalculated) cumulative funding rate.
    /// @param liquidationFeeRatio The liquidation fee of the system.
    /// @param liquidationBufferRatio The liquidation buffer ratio of the system.
    /// @param liquidationFeeUpperBound The maximum liquidation fee to be paid to the keepers.
    /// @param currentPrice Current price of the collateral asset.
    function _approxLiquidationPrice(
        FlatcoinStructs.Position memory position,
        int256 nextFundingEntry,
        uint128 liquidationFeeRatio,
        uint128 liquidationBufferRatio,
        uint256 liquidationFeeLowerBound,
        uint256 liquidationFeeUpperBound,
        uint256 currentPrice
    ) internal pure returns (uint256) {
        if (position.additionalSize == 0) {
            return 0;
        }

        FlatcoinStructs.PositionSummary memory positionSummary = _getPositionSummary(
            position,
            nextFundingEntry,
            currentPrice
        );

        int256 result = _calcLiquidationPrice(
            position,
            positionSummary,
            _liquidationMargin(
                position.additionalSize,
                liquidationFeeRatio,
                liquidationBufferRatio,
                liquidationFeeLowerBound,
                liquidationFeeUpperBound,
                currentPrice
            )
        );

        return (result > 0) ? uint256(result) : 0;
    }

    function _canLiquidate(
        FlatcoinStructs.Position memory position,
        uint128 liquidationFeeRatio,
        uint128 liquidationBufferRatio,
        uint256 liquidationFeeLowerBound,
        uint256 liquidationFeeUpperBound,
        int256 nextFundingEntry,
        uint256 currentPrice
    ) internal pure returns (bool) {
        // No liquidations of empty positions.
        if (position.additionalSize == 0) {
            return false;
        }

        FlatcoinStructs.PositionSummary memory positionSummary = _getPositionSummary(
            position,
            nextFundingEntry,
            currentPrice
        );

        uint256 lMargin = _liquidationMargin(
            position.additionalSize,
            liquidationFeeRatio,
            liquidationBufferRatio,
            liquidationFeeLowerBound,
            liquidationFeeUpperBound,
            currentPrice
        );

        return positionSummary.marginAfterSettlement <= int256(lMargin);
    }

    function _calcLiquidationPrice(
        FlatcoinStructs.Position memory position,
        FlatcoinStructs.PositionSummary memory positionSummary,
        uint256 liquidationMargin
    ) internal pure returns (int256) {
        // A position can be liquidated whenever:- remainingMargin <= liquidationMargin
        //
        // Hence, expanding the definition of remainingMargin the exact price at which a position can be liquidated is:
        //
        // liquidationMargin = margin + profitLoss + funding
        // liquidationMargin = margin + [(price - entryPrice) * postionSize / price] + funding
        // liquidationMargin - (margin + funding) = [(price - entryPrice) * postionSize / price]
        // liquidationMargin - (margin + funding) = postionSize - (entryPrice * postionSize / price)
        // positionSize - [liquidationMargin - (margin + funding)] = entryPrice * postionSize / price
        // positionSize * entryPrice / {positionSize - [liquidationMargin - (margin + funding)]} = price
        //
        // In our case, positionSize = position.additionalSize.
        // Note: If there are bounds on `liquidationFee` and/or `keeperFee` then this formula doesn't yield an accurate liquidation price.
        // This is because, when the position size is too large such that liquidation fee for that position has to be bounded we are essentially
        // solving the following equation:
        // LiquidationBuffer + (LiquidationUpperBound / Price) + KeeperFee = Margin + (Price - EntryPrice)*PositionSize + AccruedFunding
        // And according to Wolfram Alpha, this equation cannot be solved for Price (at least trivially):
        // https://www.wolframalpha.com/input?i=A+++(B+/+X)+%3D+C+++(X+-+D)+*+E+,+X+%3E+0,+Solution+for+variable+X
        int256 result = int256((position.additionalSize)._multiplyDecimal(position.entryPrice))._divideDecimal(
            int256(position.additionalSize + position.marginDeposited) +
                positionSummary.accruedFunding -
                int256(liquidationMargin)
        );

        return result;
    }

    /// The minimal margin at which liquidation can happen.
    /// Is the sum of liquidationBuffer, liquidationFee (for flagger) and keeperLiquidationFee (for liquidator)
    /// @param positionSize size of position in fixed point decimal collateral asset units.
    /// @param liquidationFeeRatio ratio of the position size to be charged as fee.
    /// @param liquidationBufferRatio ratio of the position size needed to be maintained as buffer.
    /// @param liquidationFeeUpperBound maximum fee to be charged in collateral asset units.
    /// @param currentPrice current price of the collateral asset in USD units.
    /// @return lMargin liquidation margin to maintain in collateral asset units.
    /// @dev The liquidation margin contains a buffer that is proportional to the position
    /// size. The buffer should prevent liquidation happening at negative margin (due to next price being worse)
    /// so that stakers would not leak value to liquidators through minting rewards that are not from the
    /// account's margin.
    function _liquidationMargin(
        uint256 positionSize,
        uint128 liquidationFeeRatio,
        uint128 liquidationBufferRatio,
        uint256 liquidationFeeLowerBound,
        uint256 liquidationFeeUpperBound,
        uint256 currentPrice
    ) internal pure returns (uint256 lMargin) {
        uint256 liquidationBuffer = positionSize._multiplyDecimal(liquidationBufferRatio);

        // The liquidation margin consists of the liquidation buffer, liquidation fee and the keeper fee for covering execution costs.
        return
            liquidationBuffer +
            _liquidationFee(
                positionSize,
                liquidationFeeRatio,
                liquidationFeeLowerBound,
                liquidationFeeUpperBound,
                currentPrice
            );
    }

    /// The fee charged from the margin during liquidation. Fee is proportional to position size.
    /// @dev There is a cap on the fee to prevent liquidators from being overpayed.
    /// @param positionSize size of position in fixed point decimal baseAsset units.
    /// @param liquidationFeeRatio ratio of the position size to be charged as fee.
    /// @param liquidationFeeUpperBound maximum fee to be charged in USD units.
    /// @return liquidationFee liquidation fee to be paid to liquidator in collateral asset units.
    function _liquidationFee(
        uint256 positionSize,
        uint128 liquidationFeeRatio,
        uint256 liquidationFeeLowerBound,
        uint256 liquidationFeeUpperBound,
        uint256 currentPrice
    ) internal pure returns (uint256 liquidationFee) {
        // size * price * fee-ratio
        uint256 proportionalFee = positionSize._multiplyDecimal(liquidationFeeRatio)._multiplyDecimal(currentPrice);
        uint256 cappedProportionalFee = proportionalFee > liquidationFeeUpperBound
            ? liquidationFeeUpperBound
            : proportionalFee;

        uint256 lFeeUSD = cappedProportionalFee < liquidationFeeLowerBound
            ? liquidationFeeLowerBound
            : cappedProportionalFee;

        // Return liquidation fee in collateral asset units.
        return (lFeeUSD * 1e18) / currentPrice;
    }

    /********************************************
     *                Utilities                 *
     ********************************************/

    /*
     * True if and only if two positions a and b are on the same side of the market; that is, if they have the same
     * sign, or either of them is zero.
     */
    function _sameSide(int256 a, int256 b) internal pure returns (bool) {
        return (a == 0) || (b == 0) || (a > 0) == (b > 0);
    }
}
