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

- A shared multi-asset pool (ETH and the flagship at launch) instead of a single-token vault.
- Fee revenue that does not depend only on one token's trading volume.
- A cleaner story for disclosure (view keys, proof of payment) and for integrators (open exit-target SDK).

Read `docs/DESIGN.md` for the full list of decisions and open questions.

## Repository layout

```
contracts/        Solidity (Foundry). Draft interfaces only for now.
circuits/         Noir circuit notes and, later, the circuit itself.
docs/             Design, roadmap, trust model, brand.
legacy/v0/ Reference copies of the v0 contracts. Not compiled.
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
- Claim privacy we cannot deliver. Prompts, IP addresses and timing can still be visible to services you connect to. Opaque hides who paid, not what you send.

## Status

Nothing here is audited, and nothing here is deployed. Do not use it with real funds.

## License

MIT. See `LICENSE`.
