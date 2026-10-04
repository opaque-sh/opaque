# opaque

Everything on-chain, except you.

Opaque is a privacy protocol on Robinhood Chain. Balances are opaque. The protocol is not: every rule, parameter and invariant is public and checkable.

Domain: opaque.sh | Ticker: $OPA | Status: pre-alpha, design and scaffolding

## What it is

- A shielded pool where balances live as encrypted notes. Amounts, senders and recipients stay hidden, proven with zero-knowledge proofs on the user's own device.
- A flagship coin ($OPA), an ordinary ERC-20 launched on Pons. Private holders earn from the protocol's fee stream. Public holders do not, which is the reason to shield.
- No admin keys over user funds. Contracts are not upgradeable. The only guardian power is pausing new deposits, never exits.

## Where this came from

Opaque is a rebuild of the v0 design (see `legacy/v0`). The note model, vault accounting, ERC-4337 gas abstraction and exit-target pattern carry over. What changes:

- A pool built for $OPA only: no ETH, no shield fee, and a flat unshield fee that stays in the pool for remaining holders. The note format still carries an asset id so more assets could join in a later version.
- No fee recipient in the pool. Trade fees reach the vault through a harvester (not built).
- A cleaner story for disclosure (view keys, proof of payment) and for integrators (open exit-target SDK).

Read `docs/DESIGN.md` for the full list of decisions and open questions.

## Repository layout

```
contracts/        Solidity (Foundry): OpaquePool, MerkleTree, Poseidon2Hasher, interfaces, tests.
tools/            Generators (Poseidon2 hasher from Barretenberg constants).
circuits/pool/    Noir spend circuit (draft).
docs/             Design, roadmap, trust model, brand.
legacy/v0/        Reference copies of the v0 contracts. Not compiled.
.github/          CI: forge test and nargo test.
```

## Principles

1. Nobody loses funds, and anyone can always exit.
2. Private is where holding pays.
3. Ordinary ERC-20s on the outside, so every wallet and aggregator works.
4. As few dependencies as possible, and none that can touch a note.
5. Honest numbers. Anything seeded or team-run is labeled as such.

## What we will not do

- Keep admin keys that can move, freeze or block a note.
- Ship upgradeable contracts.
- Promise a yield rate or talk about the token price.
- Post a number the chain cannot show.
- Claim privacy we cannot deliver. Prompts, IP addresses and timing can still be visible to services you connect to. Opaque hides what happens between a deposit and a withdrawal. Deposits and withdrawals are public.

## Develop

```
tools/setup-libs.sh        # pinned forge-std, v4-core, solmate, and a build of the v4 PoolManager
forge build
forge test
cd circuits/pool && nargo test
```

Contracts use solc 0.8.26. The circuit is tested with nargo 1.0.0-beta.11.

## Status

Nothing here is audited, and nothing here is deployed. Do not use it with real funds.

## License

MIT. See `LICENSE`.
