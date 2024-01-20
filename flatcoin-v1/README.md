For more in-depth docs, please visit our official [docs](https://docs.flat.money/) site!

## Motivation

The flatcoin project provides a two sided marketplace for:

- users looking for easy leverage on ETH
- users looking for a low volatility asset with real yield

## Structure

### StableModule

The stable module allows users to deposit ETH liquid staking derivative (LSD) and have a low volatility yield position.
The stable position is hedged with an equal short ETH position to the long positions in the Leverage Module.
The stable position earns yield from:

- the LSD
- trading fees on the Leverage Module

The stable position is tokenised via ERC20.

### LeverageModule

The leverage module allows a user to take a 2x - 10x (TBD) position on ETH. This is ideally collateralised with an LSD of ETH for increased capital efficiency/returns.

To ensure that the oracle is not frontrun, the contract will utilise the Pyth network for the latest price. This will execute as a delayed order by keepers. It will use a secondary Chainlink price feed for redundancy as a sanity check (ensure that the Pyth price is within a threshold of the secondary oracle).

The leverage positions are tokenised via ERC721. They contain data about the individual leverage position. This ERC721 token is customised to include locking and unlocking when announcing certain orders.

### OracleModule

The oracle can provide the LSD price via Pyth network and Chainlink oracles for the most up-to-date prices. Chainlink is only used as a sanity check in case Pyth Oracle reports inaccurate prices.

### DelayedOrder Module

This module is the primary interface for creating and executing orders for both leverage traders and stable-side LPs. Keepers monitor the contract for new order announcements and execute them using this same module. It holds the funds when orders are announced and transfers them to the vault contract after the execution of orders. It calls the stable and leverage modules to perform leverage traders and stable-side LP order executions.

### Liquidation Module

This module contains functions related to the liquidations of leverage traders. Leverage traders can call certain view functions to get their liquidation details (approx price, can liquidate, liquidation margin etc).

## How to run tests?

The codebase uses Foundry test suite and integration tests using forking mode. Set up Foundry by following the instructions in their [docs](https://book.getfoundry.sh/getting-started/installation). Make sure that you have set the relevant env variables.

Just use `forge t` to run all tests.
