// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {FlatcoinStructs} from "../libraries/FlatcoinStructs.sol";

interface ILimitOrder {
    function announceLimitOrder(uint256 tokenId, uint256 priceLowerThreshold, uint256 priceUpperThreshold) external;

    function cancelExistingLimitOrder(uint256 tokenId) external returns (bool cancelled);

    function cancelLimitOrder(uint256 tokenId) external;

    function executeLimitOrder(uint256 tokenId, bytes[] memory priceUpdateData) external payable;

    function getLimitOrder(uint256 tokenId) external view returns (FlatcoinStructs.Order memory order);
}
