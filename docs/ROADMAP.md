# Roadmap

Order matters. Later items are plans, not promises.

## Live

- Shrouded pool for $OPA on Robinhood Chain: shroud, unshroud to any address, proofs built in the browser.
- Holder yield: the unshroud fee stays in the pool, so every note still shrouded gains value.
- Deposit cap schedule fixed in the contract: starts at 50,000,000 $OPA, rises 5,000,000 every 7 days, ceiling 100,000,000.
- Immutable pool with no admin. The guardian can only pause new shrouds.

## Next

- **Harvester.** Claims Pons creator fees, buys $OPA in capped steps and donates it to the pool. Tested on a fork. It deploys after the first 24 hours of manual fee handling, using `DeployHarvester.s.sol`, followed by `transferCreatorFeeRecipient` on the Pons factory. The Pons buyback controller is checked first.
- **Relayers.** Gasless transactions, first through a relayer service and then ERC-4337 paymasters, followed by private sending without wallet gas.
- Invariants page, live funds-lost dashboard, scaling bounty.

## Then

- **Private AI payments.** Inference paid in $OPA over x402. Blind-signed, Privacy Pass style tokens bought by spending notes, redeemed at a gateway. A new exit target, not a change to the pool. Orbio is a candidate gateway.
- **Private swaps.** More exit target implementations (Uniswap v4 and aggregators) so shrouded $OPA can move into other Robinhood Chain tokens. Exit-target SDK and a reference target come first.

## Later

- **Opaque Pools.** A launchpad for privacy coins that share the same shrouded pool.
- ERC-4337 account support for shrouded balances.

## Research

Open directions, each with its own note in `docs/research`:

- Quantum-safe notes: hybrid key exchange first, then lattice and hash-based notes.
- Forward-secure signatures and epoch keys.
- Healing privacy: linkability that decays over time.
- Stealth channels.
- Adaptive security parameters.
- Computing on shrouded balances.
- Private cross-chain movement.

## Cut

- Private credit score.
- Shrouded backer stakes.
- Private governance.
