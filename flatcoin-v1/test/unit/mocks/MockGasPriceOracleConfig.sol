// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

contract MockGasPriceOracleConfig {
    // Snapshot of variables from the public Optimism mainnet gas price oracle contract
    uint256 public gasPrice = 60;
    uint256 public overhead = 188;
    uint256 public l1BaseFee = 15093270045;
    uint256 public decimals = 6;
    uint256 public scalar = 684000;

    // Settings on Base Goerli testnet, for reference
    // uint256 public gasPrice = 50;
    // uint256 public overhead = 2_100;
    // uint256 public l1BaseFee = 15;
    // uint256 public decimals = 6;
    // uint256 public scalar = 1_000_000;
}
