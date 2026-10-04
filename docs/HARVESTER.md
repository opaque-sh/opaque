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

The Pons signatures were first taken from the Pons v2 docs and the v0 documentation. On 2026-10-04 the factory, meme hook, fee escrow and curve were compared with their verified ABIs.

| Call | Where | Status |
| --- | --- | --- |
| `getLaunchedToken(address)` and the field order of the struct in `pons/IPons.sol` | factory | Matches the verified ABI |
| `memeHook()` | factory | Matches |
| `transferCreatorFeeRecipient(address token, address newRecipient)` | factory | Matches. Reverts `NotCreatorFeeRecipient` for anyone but the current recipient |
| `sweepPoolFees(bytes32 poolId, uint256, uint256)` | meme hook | Matches (`PoolId` is `bytes32`) |
| `balanceOf(address)`, `claim()` | fee escrow | Match. `claim` is overloaded (`claim(uint256)` also exists), the no-argument form is the one used |
| `buy(uint256 quoteIn, uint256 minTokensOut, address recipient)` payable | curve | Matches the verified ABI |
| `getReserves()`, `feeBps()`, `creatorTaxBps()`, `readyToGraduate()`, `sweepFees(uint256)` | curve | Matches the verified ABI |

Things the ABIs show that matter:

- **Sweeps may need Pons' operator.** The hook has `InternalSwapRequiresOperator` and `NotFeeSweepOperator`. A sweep that needs an internal swap (turning token-denominated fees into ETH, or running a buyback) can only be run by Pons' operator. The harvester's sweep sits in a `try`, so it simply fails and the fees wait until the operator sweeps them. Claiming works either way.
- **Pons can propose a new fee recipient.** The factory has `setCreatorFeeRecipient`, `pendingCreatorFeeRecipient(token)`, `executeCreatorFeeRecipientChange` and `cancelCreatorFeeRecipientChange`, with a timelock and an execution window. The harvester has no way to cancel a proposal. Watch `pendingCreatorFeeRecipient(token)` after launch. Fees already credited to the harvester stay claimable.
- **Pons' own buyback toggle.** `setBuybackEnabled(token, enabled)` exists on the factory and reverts `NotBuybackController` for others. It is not yet confirmed who the controller is. If it is the original deployer wallet, that wallet could switch buybacks on later and divert part of the creator share into Pons' vest. Check the function's source on the explorer before launch, and check `getLaunchedToken(token).buybackEnabled` after.
- **Pool fees.** The hook has its own `hookFeeBps` and can take a fee on swaps. The harvester uses the swap's returned balance delta, so the fee is already counted, but it is only tested here against a pool with no hook.
- **Not yet tried on a live pool.** The graduated pool's key and whether its hook accepts a swap from a contract with empty `hookData` are untested. Run one small buy on a fork or testnet before deploying for real.

Two more things to confirm on a live token: the curve's real price formula and snipe tax (the harvester relies only on `minTokensOut`, so a wrong assumption makes buys revert and skip, never overpay), and that the Pons v4 pool uses the key `(native ETH, token, poolFee, tickSpacing, memeHook)`.

Read the $OPA terms off the factory after launch: `getLaunchedToken(token)` should show `pairToken == address(0)`, `buybackEnabled == false` and `creatorTaxBps` as intended.

## Fork test against live Pons

`contracts/test/fork/PonsFork.t.sol` runs the harvester against the live Pons contracts on a fork, using a token that has already graduated. It is skipped unless `ROBINHOOD_RPC` is set:

```
ROBINHOOD_RPC=<rpc url> forge test --match-path contracts/test/fork/PonsFork.t.sol -vv
```

It checks that the constructor reads the real record, that the harvester gets a live price (so the pool key is right), and that a real buy through Pons' pool and hook fills and is donated to a throwaway pool. Set `PONS_TOKEN` to test another token. It has not been run yet.

## Launch order

1. Launch $OPA on Pons with the buyback toggle off. The creator fee recipient is a team wallet.
2. Deploy the pool with the real token address.
3. Deploy the harvester with the pool address.
4. From the team wallet, call `transferCreatorFeeRecipient(token, harvester)` on the factory.

Fees collected by the team wallet before step 4 can be donated to the pool with `donate`.
