// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

interface IPointsModule {
    function mintLeverageOpen(address to, uint256 size) external;

    function mintDeposit(address to, uint256 depositAmount) external;
}
