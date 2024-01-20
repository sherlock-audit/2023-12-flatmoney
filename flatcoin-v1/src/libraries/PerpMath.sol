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
library PerpMath {
    using SignedMath for int256;
    using DecimalMath for int256;
    using DecimalMath for uint256;

    /////////////////////////////////////////////
    //           Funding Math Functions        //
    /////////////////////////////////////////////

    /// @dev Returns the pSkew = skew / skewScale capping the pSkew between [-1, 1].
    /// @param skew The current system skew.
    /// @param stableCollateralTotal The total stable collateral in the system.
    /// @return pSkew The capped proportional skew.
    function _proportionalSkew(int256 skew, uint256 stableCollateralTotal) internal pure returns (int256 pSkew) {
        if (stableCollateralTotal > 0) {
            pSkew = skew._divideDecimal(int256(stableCollateralTotal));

            if (pSkew < -1e18 || pSkew > 1e18) {
                pSkew = DecimalMath.UNIT.min(pSkew.max(-DecimalMath.UNIT));
            }
        } else {
            assert(skew == 0);
            pSkew = 0;
        }
    }

    /// @dev Retrieves the change in funding rate since the last re-computation.
    ///      There is no variance in computation but will be affected based on outside modifications to
    ///      the market skew, max funding velocity, and time delta.
    /// @param proportionalSkew The capped proportional skew.
    /// @param prevFundingModTimestamp The last recomputed funding timestamp.
    /// @param maxFundingVelocity The maximum funding velocity.
    /// @param maxVelocitySkew The maximum velocity skew.
    /// @return fundingChange The change in funding rate since the last re-computation.
    function _fundingChangeSinceRecomputed(
        int256 proportionalSkew,
        uint256 prevFundingModTimestamp,
        uint256 maxFundingVelocity,
        uint256 maxVelocitySkew
    ) internal view returns (int256 fundingChange) {
        return
            _currentFundingVelocity(proportionalSkew, maxFundingVelocity, maxVelocitySkew)._multiplyDecimal(
                int256(_proportionalElapsedTime(prevFundingModTimestamp))
            );
    }

    /// @dev Function to calculate the funding rate based on market conditions.
    /// @param lastRecomputedFundingRate The last recomputed funding rate.
    /// @param lastRecomputedFundingTimestamp The last recomputed funding timestamp.
    /// @param proportionalSkew The capped proportional skew.
    /// @param maxFundingVelocity The maximum funding velocity.
    /// @param maxVelocitySkew The maximum velocity skew.
    /// @return currFundingRate The current funding rate.
    function _currentFundingRate(
        int256 lastRecomputedFundingRate,
        uint64 lastRecomputedFundingTimestamp,
        int256 proportionalSkew,
        uint256 maxFundingVelocity,
        uint256 maxVelocitySkew
    ) internal view returns (int256 currFundingRate) {
        return
            lastRecomputedFundingRate +
            _fundingChangeSinceRecomputed(
                proportionalSkew,
                lastRecomputedFundingTimestamp,
                maxFundingVelocity,
                maxVelocitySkew
            );
    }

    /// @dev Calculates the sum of the unrecorded funding rates since the last funding re-computation.
    /// @param vaultSummary The current summary of the vault state.
    /// @param maxFundingVelocity The maximum funding velocity.
    /// @param maxVelocitySkew The maximum velocity skew.
    /// @return unrecordedFunding The sum of the unrecorded funding rates since the last funding re-computation.
    function _unrecordedFunding(
        FlatcoinStructs.VaultSummary memory vaultSummary,
        uint256 maxFundingVelocity,
        uint256 maxVelocitySkew
    ) internal view returns (int256 unrecordedFunding) {
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

    /// @dev Same as the above `_unrecordedFunding but with the current funding rate passed in.
    /// @param currentFundingRate The current funding rate.
    /// @param prevFundingRate The previous funding rate.
    /// @param prevFundingModTimestamp The last recomputed funding timestamp.
    /// @return unrecordedFunding The sum of the unrecorded funding rates since the last funding re-computation.
    function _unrecordedFunding(
        int256 currentFundingRate,
        int256 prevFundingRate,
        uint256 prevFundingModTimestamp
    ) internal view returns (int256 unrecordedFunding) {
        int256 avgFundingRate = (prevFundingRate + currentFundingRate) / 2;

        return avgFundingRate._multiplyDecimal(int256(_proportionalElapsedTime(prevFundingModTimestamp)));
    }

    /// @dev The new entry in the funding sequence, appended when funding is recomputed.
    ///      It is the sum of the last entry and the unrecorded funding,
    ///      so the sequence accumulates running total over the market's lifetime.
    /// @param vaultSummary The current summary of the vault state.
    /// @param maxFundingVelocity The maximum funding velocity.
    /// @param maxVelocitySkew The maximum velocity skew.
    /// @return nextFundingEntry The next entry in the funding sequence.
    function _nextFundingEntry(
        FlatcoinStructs.VaultSummary memory vaultSummary,
        uint256 maxFundingVelocity,
        uint256 maxVelocitySkew
    ) internal view returns (int256 nextFundingEntry) {
        return
            vaultSummary.cumulativeFundingRate + _unrecordedFunding(vaultSummary, maxFundingVelocity, maxVelocitySkew);
    }

    /// @dev Same as the above `_nextFundingEntry` but with the next funding entry passed in.
    /// @param unrecordedFunding The sum of the unrecorded funding rates since the last funding re-computation.
    /// @param latestFundingSequenceEntry The latest funding sequence entry.
    /// @return nextFundingEntry The next entry in the funding sequence.
    function _nextFundingEntry(
        int256 unrecordedFunding,
        int256 latestFundingSequenceEntry
    ) internal pure returns (int256 nextFundingEntry) {
        return latestFundingSequenceEntry + unrecordedFunding;
    }

    /// @dev Calculates the current net funding per unit for a position.
    /// @param userFundingSequenceEntry The user's last funding sequence entry.
    /// @param nextFundingEntry The next funding sequence entry.
    /// @return netFundingPerUnit The net funding per unit for a position.
    function _netFundingPerUnit(
        int256 userFundingSequenceEntry,
        int256 nextFundingEntry
    ) internal pure returns (int256 netFundingPerUnit) {
        return userFundingSequenceEntry - nextFundingEntry;
    }

    /*******************************************
     *             Position Details             *
     *******************************************/

    /// @dev Returns the PnL in terms of the market currency (ETH/LST) and not in dollars ($).
    ///      This function rounds down the PnL to avoid rounding errors when subtracting individual PnLs
    ///      from the global `marginDepositedTotal` value when closing the position.
    /// @param position The position to calculate the PnL for.
    /// @param price The current price of the collateral asset.
    /// @return pnl The PnL in terms of the market currency (ETH/LST) and not in dollars ($).
    function _profitLoss(FlatcoinStructs.Position memory position, uint256 price) internal pure returns (int256 pnl) {
        int256 priceShift = int256(price) - int256(position.lastPrice);
        int256 profitLossTimesTen = (int256(position.additionalSize) * (priceShift) * 10) / int256(price);

        if (profitLossTimesTen % 10 != 0) {
            return profitLossTimesTen / 10 - 1;
        } else {
            return profitLossTimesTen / 10;
        }
    }

    /// @dev Returns the PnL in terms of the market currency (ETH/LST) and not in dollars ($).
    ///      This function rounds down the funding accrued to avoid rounding errors when subtracting individual funding fees accrued
    ///      from the global `marginDepositedTotal` value when closing the position.
    /// @param globalPosition The global position to calculate the PnL for.
    /// @param price The current price of the collateral asset.
    /// @return pnl The PnL in terms of the market currency (ETH/LST) and not in dollars ($).
    function _profitLossTotal(
        FlatcoinStructs.GlobalPositions memory globalPosition,
        uint256 price
    ) internal pure returns (int256 pnl) {
        int256 priceShift = int256(price) - int256(globalPosition.lastPrice);

        return (int256(globalPosition.sizeOpenedTotal) * (priceShift)) / int256(price);
    }

    function _accruedFunding(
        FlatcoinStructs.Position memory position,
        int256 nextFundingEntry
    ) internal pure returns (int256 accruedFunding) {
        int256 net = _netFundingPerUnit(position.entryCumulativeFunding, nextFundingEntry);
        int256 accruedFundingTimesTen = int256(position.additionalSize * 10)._multiplyDecimal(net);

        if (accruedFundingTimesTen % 10 != 0) {
            return accruedFundingTimesTen / 10 - 1;
        } else {
            return accruedFundingTimesTen / 10;
        }
    }

    /// @dev Calculates the funding fees accrued by the global position (all leverage traders).
    /// @param globalPosition The global position to calculate the funding fees accrued for.
    /// @param unrecordedFunding The sum of the unrecorded funding rates since the last funding re-computation.
    /// @return accruedFundingLongs The funding fees accrued by the global position (all leverage traders).
    function _accruedFundingTotalByLongs(
        FlatcoinStructs.GlobalPositions memory globalPosition,
        int256 unrecordedFunding
    ) internal pure returns (int256 accruedFundingLongs) {
        return -int256(globalPosition.sizeOpenedTotal)._multiplyDecimal(unrecordedFunding);
    }

    /// @dev Summarises a positions' earnings/losses.
    /// @param position The position to summarise.
    /// @param nextFundingEntry The next (recalculated) cumulative funding rate.
    /// @param price The current price of the collateral asset.
    /// @return positionSummary The summary of the position.
    function _getPositionSummary(
        FlatcoinStructs.Position memory position,
        int256 nextFundingEntry,
        uint256 price
    ) internal pure returns (FlatcoinStructs.PositionSummary memory positionSummary) {
        int256 profitLoss = _profitLoss(position, price);
        int256 accruedFunding = _accruedFunding(position, nextFundingEntry);

        return
            FlatcoinStructs.PositionSummary({
                profitLoss: profitLoss,
                accruedFunding: accruedFunding,
                marginAfterSettlement: int256(position.marginDeposited) + profitLoss + accruedFunding
            });
    }

    /// @dev Summarises the market state which is used in other functions.
    /// @param vaultSummary The current summary of the vault state.
    /// @param maxFundingVelocity The maximum funding velocity.
    /// @param maxVelocitySkew The maximum velocity skew.
    /// @param price The current price of the collateral asset.
    /// @return marketSummary The summary of the market.
    function _getMarketSummaryLongs(
        FlatcoinStructs.VaultSummary memory vaultSummary,
        uint256 maxFundingVelocity,
        uint256 maxVelocitySkew,
        uint256 price
    ) internal view returns (FlatcoinStructs.MarketSummary memory marketSummary) {
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

    /////////////////////////////////////////////
    //            Liquidation Math             //
    /////////////////////////////////////////////

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
    ) internal pure returns (uint256 approxLiquidationPrice) {
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

    /// @dev Function to get the liquidation status of a position.
    /// @param position The position to check the liquidation status for.
    /// @param liquidationFeeRatio The liquidation fee of the system.
    /// @param liquidationBufferRatio The liquidation buffer ratio of the system.
    /// @param liquidationFeeLowerBound The minimum liquidation fee to be paid to the flagger.
    /// @param liquidationFeeUpperBound The maximum liquidation fee to be paid to the keepers.
    /// @param nextFundingEntry The next (recalculated) cumulative funding rate.
    /// @param currentPrice Current price of the collateral asset.
    /// @return isLiquidatable Whether the position is liquidatable.
    function _canLiquidate(
        FlatcoinStructs.Position memory position,
        uint128 liquidationFeeRatio,
        uint128 liquidationBufferRatio,
        uint256 liquidationFeeLowerBound,
        uint256 liquidationFeeUpperBound,
        int256 nextFundingEntry,
        uint256 currentPrice
    ) internal pure returns (bool isLiquidatable) {
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

    /// @dev The minimal margin at which liquidation can happen.
    ///      Is the sum of liquidationBuffer, liquidationFee (for flagger) and keeperLiquidationFee (for liquidator)
    ///      The liquidation margin contains a buffer that is proportional to the position
    ///      size. The buffer should prevent liquidation happening at negative margin (due to next price being worse).
    /// @param positionSize size of position in fixed point decimal collateral asset units.
    /// @param liquidationFeeRatio ratio of the position size to be charged as fee.
    /// @param liquidationBufferRatio ratio of the position size needed to be maintained as buffer.
    /// @param liquidationFeeUpperBound maximum fee to be charged in collateral asset units.
    /// @param currentPrice current price of the collateral asset in USD units.
    /// @return lMargin liquidation margin to maintain in collateral asset units.
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

    /////////////////////////////////////////////
    //            Private Functions            //
    /////////////////////////////////////////////

    /// @dev The funding velocity is based on the market skew and is scaled by the maxVelocitySkew.
    ///      With higher skews beyond the maxVelocitySkew, the velocity remains constant.
    /// @param proportionalSkew The calculated capped proportional skew.
    /// @param maxFundingVelocity The maximum funding velocity.
    /// @param maxVelocitySkew The maximum velocity skew.
    function _currentFundingVelocity(
        int256 proportionalSkew,
        uint256 maxFundingVelocity,
        uint256 maxVelocitySkew
    ) private pure returns (int256 currFundingVelocity) {
        if (maxVelocitySkew > 0) {
            // Scale the funding velocity by the maxVelocitySkew and cap it at the maximum +- velocity.
            int256 fundingVelocity = (proportionalSkew * int256(maxFundingVelocity)) / int256(maxVelocitySkew);
            return int256(maxFundingVelocity).min(fundingVelocity.max(-int256(maxFundingVelocity)));
        }

        return proportionalSkew._multiplyDecimal(int256(maxFundingVelocity));
    }

    /// @dev Returns the time delta between the last funding timestamp and the current timestamp.
    /// @param prevModTimestamp The last funding timestamp.
    /// @return elapsedTime The time delta between the last funding timestamp and the current timestamp.
    function _proportionalElapsedTime(uint256 prevModTimestamp) private view returns (uint256 elapsedTime) {
        return (block.timestamp - prevModTimestamp)._divideDecimal(1 days);
    }

    /// @dev Calculates the liquidation price.
    /// @param position The position to calculate the liquidation price for.
    /// @param positionSummary The summary of the position.
    /// @param liquidationMargin The liquidation margin.
    /// @return liqPrice The liquidation price.
    function _calcLiquidationPrice(
        FlatcoinStructs.Position memory position,
        FlatcoinStructs.PositionSummary memory positionSummary,
        uint256 liquidationMargin
    ) private pure returns (int256 liqPrice) {
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
        return
            int256((position.additionalSize)._multiplyDecimal(position.lastPrice))._divideDecimal(
                int256(position.additionalSize + position.marginDeposited) +
                    positionSummary.accruedFunding -
                    int256(liquidationMargin)
            );
    }
}
