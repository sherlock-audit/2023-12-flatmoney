// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IPointsModule {
    struct MintPoints {
        address to;
        uint256 amount;
    }

    function getUnlockTax(address account) external view returns (uint256 unlockTax);

    function lockedBalance(address account) external view returns (uint256 amount);

    function mintDeposit(address to, uint256 depositAmount) external;

    function mintLeverageOpen(address to, uint256 size) external;

    function mintTo(MintPoints memory _mintPoints) external;

    function mintToMultiple(MintPoints[] memory _mintPoints) external;

    function pointsPerDeposit() external view returns (uint256 depositPoints);

    function pointsPerSize() external view returns (uint256 sizePoints);

    function setPointsVest(uint256 _unlockTaxVest, uint256 _pointsPerSize, uint256 _pointsPerDeposit) external;

    function setTreasury(address _treasury) external;

    function treasury() external view returns (address treasury);

    function unlock(uint256 amount) external;

    function unlockAll() external;

    function unlockTaxVest() external view returns (uint256 unlockTaxVest);

    function unlockTime(address account) external view returns (uint256 unlockTime);
}
