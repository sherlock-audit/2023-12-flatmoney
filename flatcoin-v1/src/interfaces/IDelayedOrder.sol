// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {FlatcoinStructs} from "../libraries/FlatcoinStructs.sol";

interface IDelayedOrder {
    function announceStableDeposit(uint256 depositAmount, uint256 minAmountOut, uint256 keeperFee) external;

    function announceStableWithdraw(uint256 withdrawAmount, uint256 minAmountOut, uint256 keeperFee) external;

    function announceLeverageOpen(
        uint256 margin,
        uint256 additionalSize,
        uint256 maxFillPrice,
        uint256 keeperFee
    ) external;

    function announceLeverageAdjust(
        uint256 tokenId,
        int256 marginAdjustment,
        int256 additionalSizeAdjustment,
        uint256 fillPrice,
        uint256 keeperFee
    ) external;

    function announceLeverageClose(uint256 tokenId, uint256 minFillPrice, uint256 keeperFee) external;

    function getAnnouncedOrder(address account) external view returns (FlatcoinStructs.Order memory order);
}
