// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {FlatcoinStructs} from "../libraries/FlatcoinStructs.sol";

interface IFlatcoinVault {
    function collateral() external view returns (IERC20Upgradeable collateral);

    function lastRecomputedFundingTimestamp() external view returns (uint64 lastRecomputedFundingTimestamp);

    function minExecutabilityAge() external view returns (uint64 minExecutabilityAge);

    function maxExecutabilityAge() external view returns (uint64 maxExecutabilityAge);

    function lastRecomputedFundingRate() external view returns (int256 lastRecomputedFundingRate);

    function cumulativeFundingRate() external view returns (int256 cumulativeFundingRate);

    function maxFundingVelocity() external view returns (uint256 maxFundingVelocity);

    function maxVelocitySkew() external view returns (uint256 maxVelocitySkew);

    function stableCollateralTotal() external view returns (uint256 totalAmount);

    function skewFractionMax() external view returns (uint256 skewFractionMax);

    function moduleAddress(bytes32 _moduleKey) external view returns (address moduleAddress);

    function isAuthorizedModule(address _address) external view returns (bool status);

    function isModulePaused(bytes32 moduleKey) external view returns (bool paused);

    function sendCollateral(address to, uint256 amount) external;

    function getVaultSummary() external view returns (FlatcoinStructs.VaultSummary memory _vaultSummary);

    function getGlobalPositions() external view returns (FlatcoinStructs.GlobalPositions memory _globalPositions);

    function setPosition(FlatcoinStructs.Position memory _position, uint256 _tokenId) external;

    function updateGlobalPositionData(uint256 price, int256 marginDelta, int256 additionalSizeDelta) external;

    function updateStableCollateralTotal(int256 _stableCollateralAdjustment) external;

    function addAuthorizedModules(FlatcoinStructs.AuthorizedModule[] calldata _modules) external;

    function addAuthorizedModule(FlatcoinStructs.AuthorizedModule calldata _module) external;

    function removeAuthorizedModule(bytes32 _moduleKey) external;

    function deletePosition(uint256 _tokenId) external;

    function settleFundingFees() external returns (int256 fundingFees);

    function getCurrentFundingRate() external view returns (int256 fundingRate);

    function getPosition(uint256 _tokenId) external view returns (FlatcoinStructs.Position memory position);

    function checkSkewMax(uint256 additionalSkew) external view;

    function checkCollateralCap(uint256 depositAmount) external view;

    function stableCollateralCap() external view returns (uint256 collateralCap);

    function getCurrentSkew() external view returns (int256 skew);
}
