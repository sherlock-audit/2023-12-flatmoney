// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {IKeeperFee} from "../../../src/interfaces/IKeeperFee.sol";

contract MockKeeperFee is IKeeperFee {
    uint256 private _profitMarginUSD = 1e18;
    uint256 private _profitMarginPercent = 3e18;
    uint256 private _keeperFeeUpperBound = 50e18; // $50
    uint256 private _keeperFeeLowerBound = 4e18; // $4
    uint256 private _gasUnitsL1 = 30_000;
    uint256 private _gasUnitsL2 = 1_200_000;

    function getKeeperFee() public pure returns (uint256 keeperFee) {
        keeperFee = 0.001e18; // mock 0.001 ETH
    }

    function getConfig()
        public
        view
        returns (
            uint256 profitMarginUSD,
            uint256 profitMarginPercent,
            uint256 minKeeperFeeUpperBound,
            uint256 minKeeperFeeLowerBound,
            uint256 gasUnitsL1,
            uint256 gasUnitsL2
        )
    {
        return (
            _profitMarginUSD,
            _profitMarginPercent,
            _keeperFeeUpperBound,
            _keeperFeeLowerBound,
            _gasUnitsL1,
            _gasUnitsL2
        );
    }

    function setParameters(uint256 keeperFeeUpperBound, uint256 keeperFeeLowerBound) external {
        _keeperFeeUpperBound = keeperFeeUpperBound;
        _keeperFeeLowerBound = keeperFeeLowerBound;
    }
}
