// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {FlatcoinStructs} from "../libraries/FlatcoinStructs.sol";

interface IDelayedOrder {
    // solhint-disable-next-line func-name-mixedcase
    function MIN_DEPOSIT() external view returns (uint256 minStableDeposit);

    function announceLeverageAdjust(
        uint256 tokenId,
        int256 marginAdjustment,
        int256 additionalSizeAdjustment,
        uint256 fillPrice,
        uint256 keeperFee
    ) external;

    function announceLeverageClose(uint256 tokenId, uint256 minFillPrice, uint256 keeperFee) external;

    function announceLeverageOpen(
        uint256 margin,
        uint256 additionalSize,
        uint256 maxFillPrice,
        uint256 keeperFee
    ) external;

    function announceStableDeposit(uint256 depositAmount, uint256 minAmountOut, uint256 keeperFee) external;

    function announceStableWithdraw(uint256 withdrawAmount, uint256 minAmountOut, uint256 keeperFee) external;

    function cancelExistingOrder(address account) external;

    function executeOrder(address account, bytes[] memory priceUpdateData) external payable;

    function getAnnouncedOrder(address account) external view returns (FlatcoinStructs.Order memory order);

    function hasOrderExpired(address account) external view returns (bool expired);
}
