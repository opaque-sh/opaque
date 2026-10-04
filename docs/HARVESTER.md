# Harvester

`contracts/src/OpaqueHarvester.sol` is meant to be $OPA's Pons creator fee recipient. Anyone can call `harvest()`.

## What it does

1. Sweeps the fees Pons holds for $OPA (curve before graduation, hook after) and claims the ETH from the fee escrow. Each sweep sits in a `try`, so none can block a harvest.
2. Owes the team `teamShareBps` of what it just collected. The share is fixed at deployment.
3. Spends the rest on $OPA in small steps and donates it to `OpaquePool`, which raises every share's value.
4. Refunds the caller its gas, capped at 0.5% of the ETH it put to work.

Buying rules: at most one buy per block, sized to move the price by about 0.5% or less (from the pool's active liquidity or the curve's ETH reserve), and never more than 15% dearer than the harvester's own price average. A size the market will not fill within those bounds is halved up to 8 times, then skipped. Skipped ETH waits for the next harvest. No venue is live in the swept phase (between graduation and pool creation), so nothing is bought then.

## Who can do what

- The **owner** can change the team's payout address, propose a successor (public, executable by anyone after 24 hours), cancel it, hand ownership on, or renounce it.
- A successor, once executed, becomes Pons' creator fee recipient and decides where all future fees go. Renouncing ownership removes this path for good.
- Pons' own takeover process can also move the recipient, and the harvester cannot stop it. This must stay in the trust model.
- Nobody can touch notes or tokens already donated to the pool.

## Status

Written and tested (28 tests against mocks of the Pons contracts, 5 against a real Uniswap v4 PoolManager). Not audited. **Not run against the live Pons contracts.**

## Check before deploying

The Pons signatures were taken from the Pons v2 docs and the v0 documentation, not from the verified ABI. Confirm each against the verified contracts on the explorer.

| Call | Where | Source |
| --- | --- | --- |
| `getLaunchedToken(address)` returning the struct in `pons/IPons.sol` (field order matters) | factory | Pons v2 docs |
| `memeHook()` | factory | v0 docs |
| `transferCreatorFeeRecipient(address token, address newRecipient)` | factory | Pons v2 docs, v0 docs |
| `buy(uint256 quoteIn, uint256 minTokensOut, address recipient)` payable | curve | Pons v2 docs |
| `getReserves()`, `feeBps()`, `creatorTaxBps()`, `readyToGraduate()`, `sweepFees(uint256)` | curve | Pons v2 docs |
| `sweepPoolFees(bytes32 poolId, uint256, uint256)` | meme hook | Pons v2 docs (poolId type is assumed) |
| `balanceOf(address)`, `claim()` | fee escrow | Pons v2 docs |

If `sweepPoolFees` or `sweepFees` has a different signature, the `try` will swallow the failure and fees will still be claimable once Pons sweeps them, but the harvester will not trigger the sweep itself.

Two more things to confirm on a live token: the curve's real price formula and snipe tax (the harvester only relies on `minTokensOut`, so a wrong assumption makes buys revert and skip, never overpay), and that the Pons v4 pool uses the key `(native ETH, token, poolFee, tickSpacing, memeHook)`.

Read the $OPA terms off the factory after launch: `getLaunchedToken(token)` should show `pairToken == address(0)`, `buybackEnabled == false` and `creatorTaxBps` as intended.

## Launch order

1. Launch $OPA on Pons with the buyback toggle off. The creator fee recipient is a team wallet.
2. Deploy the pool with the real token address.
3. Deploy the harvester with the pool address.
4. From the team wallet, call `transferCreatorFeeRecipient(token, harvester)` on the factory.

Fees collected by the team wallet before step 4 can be donated to the pool with `donate`.
