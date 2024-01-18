// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {IERC721EnumerableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC721EnumerableUpgradeable.sol";
import {FlatcoinStructs} from "../libraries/FlatcoinStructs.sol";

interface ILeverageModule is IERC721EnumerableUpgradeable {
    function getPositionSummary(
        uint256 tokenId
    ) external view returns (FlatcoinStructs.PositionSummary memory positionSummary);

    function isLocked(uint256 tokenId) external view returns (bool lockStatus);

    function executeOpen(
        address account,
        address keeper,
        FlatcoinStructs.Order calldata order
    ) external returns (uint256 newTokenId);

    function executeAdjust(address account, address keeper, FlatcoinStructs.Order calldata order) external;

    function executeClose(
        address account,
        address keeper,
        FlatcoinStructs.Order calldata order
    ) external returns (int256 settledMargin);

    function burn(uint256 tokenId) external;

    function lock(uint256 tokenId) external;

    function unlock(uint256 tokenId) external;

    function fundingAdjustedLongPnLTotal() external view returns (int256 _fundingAdjustedPnL);

    function fundingAdjustedLongPnLTotal(uint32 maxAge) external view returns (int256 _fundingAdjustedPnL);

    function tokenIdNext() external view returns (uint256 tokenId);

    function levTradingFee() external view returns (uint256 levTradingFee);

    function checkLeverageCriteria(uint256 margin, uint256 size) external view;

    function marginMin() external view returns (uint256 marginMin);

    function getTradeFee(uint256 size) external view returns (uint256 tradeFee);
}
