// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

interface IOracleModule {
    function getPrice() external view returns (uint256 price, uint256 timestamp);

    function getPrice(uint32 maxAge) external view returns (uint256 price, uint256 timestamp);

    function updatePythPrice(address sender, bytes[] calldata priceUpdateData) external payable;
}
