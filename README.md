
# dHEDGE contest details

- Join [Sherlock Discord](https://discord.gg/MABEWyASkp)
- Submit findings using the issue page in your private contest repo (label issues as med or high)
- [Read for more details](https://docs.sherlock.xyz/audits/watsons)

# Q&A

### Q: On what chains are the smart contracts going to be deployed?
Base
___

### Q: Which ERC20 tokens do you expect will interact with the smart contracts? 
External ERC20: rETH
Internal ERC20: flatcoin
___

### Q: Which ERC721 tokens do you expect will interact with the smart contracts? 
External ERC721: none
Internal ERC721: leveraged positions
___

### Q: Do you plan to support ERC1155?
No
___

### Q: Which ERC777 tokens do you expect will interact with the smart contracts? 
None
___

### Q: Are there any FEE-ON-TRANSFER tokens interacting with the smart contracts?

No
___

### Q: Are there any REBASING tokens interacting with the smart contracts?

No
___

### Q: Are the admins of the protocols your contracts integrate with (if any) TRUSTED or RESTRICTED?
TRUSTED: collateral asset will be rETH, Pyth Network oracle for rETH
___

### Q: Is the admin/owner of the protocol/contracts TRUSTED or RESTRICTED?
TRUSTED: contracts are upgradeable by admin, admin can update protocol parameters
___

### Q: Are there any additional protocol roles? If yes, please explain in detail:
None other than owner role (using OwnableUpgradeable).
___

### Q: Is the code/contract expected to comply with any EIPs? Are there specific assumptions around adhering to those EIPs that Watsons should be aware of?
No
___

### Q: Please list any known issues/acceptable risks that should not result in a valid finding.
Flatcoin can decrease in dollar value when funding rates are negative and protocol fees don't cover the losses. This is acceptable.

Flatcoin can be net short and ETH goes up 5x in a short period of time, potentially leading to UNIT going to 0.
The flatcoin holders should be mostly delta neutral, but they may be up to 20% short in certain market conditions (`skewFractionMax` parameter).
The funding rate should balance this out, but theoretically, if ETH price increases by 5x in a short period of time whilst the flatcoin holders are 20% short, it's possible for flatcoin value to go to 0. This scenario is deemed to be extremely unlikely and the funding rate is able to move quickly enough to bring the flatcoin holders back to delta neutral.

When long max skew (`skewFractionMax`) is reached, flatcoin holders cannot withdraw, and no new leverage positions can be opened.
This is to prevent the flatcoin holders being increasingly short. This is temporary because the funding rate will bring the skew back to 0 and create more room for flatcoin holders to withdraw and leverage traders to open positions.
___

### Q: Please provide links to previous audits (if any).
N/A
___

### Q: Are there any off-chain mechanisms or off-chain procedures for the protocol (keeper bots, input validation expectations, etc)?
The protocol uses Pyth Network collateral (rETH) price feed. This is an offchain price that is pulled by the keeper and pushed onchain at time of any order execution.
___

### Q: In case of external protocol integrations, are the risks of external contracts pausing or executing an emergency withdrawal acceptable? If not, Watsons will submit issues related to these situations that can harm your protocol's functionality.
Only rETH and Pyth rETH oracle dependency.
___

### Q: Do you expect to use any of the following tokens with non-standard behaviour with the smart contracts?
External dependency only rETH on Base https://basescan.org/token/0xb6fe221fe9eef5aba221c348ba20a1bf5e73624c#code
___

### Q: Add links to relevant protocol resources
RocketPool depository: https://github.com/rocket-pool/rocketpool/tree/master
___



# Audit scope


[flatcoin-v1 @ ea561f48bd9eae11895fc5e4f476abe909d8a634](https://github.com/dhedge/flatcoin-v1/tree/ea561f48bd9eae11895fc5e4f476abe909d8a634)
- [flatcoin-v1/src/DelayedOrder.sol](flatcoin-v1/src/DelayedOrder.sol)
- [flatcoin-v1/src/FlatcoinVault.sol](flatcoin-v1/src/FlatcoinVault.sol)
- [flatcoin-v1/src/LeverageModule.sol](flatcoin-v1/src/LeverageModule.sol)
- [flatcoin-v1/src/LimitOrder.sol](flatcoin-v1/src/LimitOrder.sol)
- [flatcoin-v1/src/LiquidationModule.sol](flatcoin-v1/src/LiquidationModule.sol)
- [flatcoin-v1/src/OracleModule.sol](flatcoin-v1/src/OracleModule.sol)
- [flatcoin-v1/src/PointsModule.sol](flatcoin-v1/src/PointsModule.sol)
- [flatcoin-v1/src/StableModule.sol](flatcoin-v1/src/StableModule.sol)
- [flatcoin-v1/src/abstracts/ModuleUpgradeable.sol](flatcoin-v1/src/abstracts/ModuleUpgradeable.sol)
- [flatcoin-v1/src/abstracts/OracleModifiers.sol](flatcoin-v1/src/abstracts/OracleModifiers.sol)
- [flatcoin-v1/src/libraries/DecimalMath.sol](flatcoin-v1/src/libraries/DecimalMath.sol)
- [flatcoin-v1/src/libraries/FlatcoinErrors.sol](flatcoin-v1/src/libraries/FlatcoinErrors.sol)
- [flatcoin-v1/src/libraries/FlatcoinEvents.sol](flatcoin-v1/src/libraries/FlatcoinEvents.sol)
- [flatcoin-v1/src/libraries/FlatcoinModuleKeys.sol](flatcoin-v1/src/libraries/FlatcoinModuleKeys.sol)
- [flatcoin-v1/src/libraries/FlatcoinStructs.sol](flatcoin-v1/src/libraries/FlatcoinStructs.sol)
- [flatcoin-v1/src/libraries/PerpMath.sol](flatcoin-v1/src/libraries/PerpMath.sol)
- [flatcoin-v1/src/misc/ERC20LockableUpgradeable.sol](flatcoin-v1/src/misc/ERC20LockableUpgradeable.sol)
- [flatcoin-v1/src/misc/ERC721LockableEnumerableUpgradeable.sol](flatcoin-v1/src/misc/ERC721LockableEnumerableUpgradeable.sol)
- [flatcoin-v1/src/misc/InvariantChecks.sol](flatcoin-v1/src/misc/InvariantChecks.sol)
- [flatcoin-v1/src/misc/KeeperFee.sol](flatcoin-v1/src/misc/KeeperFee.sol)
- [flatcoin-v1/src/misc/Viewer.sol](flatcoin-v1/src/misc/Viewer.sol)

