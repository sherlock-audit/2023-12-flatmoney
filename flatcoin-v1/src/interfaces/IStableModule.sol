// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {FlatcoinStructs} from "../libraries/FlatcoinStructs.sol";

interface IStableModule is IERC20Upgradeable, IERC20MetadataUpgradeable {
    function stableCollateralPerShare() external view returns (uint256 collateralPerShare);

    function executeDeposit(
        address account,
        uint64 executableAtTime,
        FlatcoinStructs.AnnouncedStableDeposit calldata announcedDeposit
    ) external returns (uint256 liquidityMinted);

    function executeWithdraw(
        address account,
        uint64 executableAtTime,
        FlatcoinStructs.AnnouncedStableWithdraw calldata announcedWithdraw
    ) external returns (uint256 amountOut, uint256 withdrawFee);

    function stableWithdrawFee() external view returns (uint256 stableWithdrawFee);

    function stableDepositQuote(uint256 depositAmount) external view returns (uint256 amountOut);

    function stableWithdrawQuote(uint256 withdrawAmount) external view returns (uint256 amountOut);

    function lock(address account, uint256 amount) external;

    function unlock(address account, uint256 amount) external;

    function getLockedAmount(address account) external view returns (uint256 amountLocked);
}
