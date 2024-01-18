TODO: needs to be fleshed out.

## Motivation

The flatcoin project provides a two sided marketplace for:

- users looking for easy leverage on ETH
- users looking for a low volatility asset with real yield

## Structure

### StableModule

The stable module allows a user to deposit ETH liquid staking derivative (LSD) and have a low volatility yield position.
The stable position is hedged with an equal short ETH position to the long positions in the Leverage Module.
The stable position earns yield from:

- the LSD
- trading fees on the Leverage Module

The stable position is tokenised via ERC20.

### LeverageModule

The leverage module allows a user to take a 2x - 10x (TBD) position on ETH.
This is ideally collateralised with a LSD of ETH for increased capital efficiency / returns.

To ensure that the oracle is not frontrun, the contract will utilise the Pyth network for the latest price.
This will execute as a delayed order by keepers.
It will use a secondary price feed for redundancy as a sanity check (ensure that the Pyth price is within a threshold of the secondary oracle).

The leverage positions are tokenised via ERC721.
They contain data about the individual leverage position.

### OracleModule

The oracle can provide LSD price via Pyth network for the most up to date prices

## How to run tests?

The codebase uses Foundry test suite and integration tests using forking mode. Setup Foundry by following the instructions in their [docs](https://book.getfoundry.sh/getting-started/installation). Make sure that you have set the relevant env variables.

Foundry version confirmed to work:

```shell
$ foundryup --version nightly-0f530f2ae63342b136ad65e1c7d3b3231b939a6b
```

Enter the following command in your terminal. By default, all tests will run.

```shell
$ forge t
```

To run specific tests (integration/fuzz), use the following commands:

For integration tests

```shell
$ npm run tests:integration
```

For fuzz tests

```shell
$ npm run tests:fuzz
```
