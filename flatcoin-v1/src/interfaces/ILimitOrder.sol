// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

interface ILimitOrder {
    function cancelExistingLimitOrder(uint256 tokenId) external returns (bool cancelled);
}
