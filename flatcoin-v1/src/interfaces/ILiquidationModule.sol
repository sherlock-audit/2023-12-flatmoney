// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

interface ILiquidationModule {
    function canLiquidate(uint256 tokenId) external view returns (bool liquidatable);

    function canLiquidate(uint256 tokenId, uint256 price) external view returns (bool liquidatable);

    function getLiquidationFee(uint256 tokenId) external view returns (uint256 liquidationFee);

    function getLiquidationMargin(uint256 additionalSize) external view returns (uint256 liquidationMargin);

    function getLiquidationMargin(
        uint256 additionalSize,
        uint256 price
    ) external view returns (uint256 liquidationMargin);

    function liquidate(uint256 tokenId) external;

    function liquidate(uint256 tokenID, bytes[] memory priceUpdateData) external payable;

    function liquidationBufferRatio() external view returns (uint128 liquidationBufferRatio);

    function liquidationFeeLowerBound() external view returns (uint256 feeLowerBound);

    function liquidationFeeRatio() external view returns (uint128 liquidationFeeRatio);

    function liquidationFeeUpperBound() external view returns (uint256 feeUpperBound);

    function liquidationPrice(uint256 tokenId) external view returns (uint256 liqPrice);

    function liquidationPrice(uint256 tokenId, uint256 price) external view returns (uint256 liqPrice);

    function setLiquidationBufferRatio(uint128 _newLiquidationBufferRatio) external;

    function setLiquidationFeeRatio(uint128 _newLiquidationFeeRatio) external;
}
