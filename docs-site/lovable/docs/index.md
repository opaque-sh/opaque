---
title: Introduction
description: Opaque is a shrouded pool on Robinhood Chain. Shroud $OPA into private notes to hold and send them without putting your balance or wallet history on display, and to earn from protocol fees.
---

On most blockchains, anyone can look up an address and see what it holds and every payment it has made. $OPA is an ordinary ERC-20 on Robinhood Chain, launched on the Pons launchpad. Opaque is its private side: when you shroud $OPA, it moves into the Opaque pool and becomes a private note that only you can spend. From there you can send it, or take it back out to any address.

> [!WARNING]
> **Pre-alpha, unaudited**
>
> The contracts and the circuit are written and tested locally. They have not been audited, the on-chain verifier has not been generated yet, and the app is not live. Pages describing the app are marked as planned. Numbers on this site are illustrative.

## What makes it different

- **Private when you choose**: Shroud $OPA into notes. Balances and who pays whom inside the pool stay hidden, proven with zero-knowledge proofs. Shrouding and withdrawing are public transactions.
- **Trades like any token**: $OPA is a plain ERC-20. Wallets, exchanges and aggregators work unchanged.
- **Paid to stay private**: Fees flow to the $OPA vault behind private notes. Only notes earn. Public $OPA does not. The fee harvester that routes trade fees is written but not audited or deployed.
- **No operator**: The pool cannot be upgraded and has no admin. The one pause stops only new deposits, never spends or exits.

## How it fits together

1. **Hold.** You buy $OPA on its Pons curve, on Uniswap v4 after it graduates, or through an aggregator.
2. **Shroud.** You deposit $OPA into the pool. The deposit is public. What you receive is a private note.
3. **Earn.** Fees are donated into the vault that backs $OPA notes, so the value of each note's share rises over time. Public holders do not earn.
4. **Move.** You send notes privately, or exit to any address with a zero-knowledge proof. The exit is public.

## Where to go next

- **[Key concepts](/docs/concepts)**: Notes, nullifiers, the note tree and exits in plain words.
- **[Fees and yield](/docs/fees)**: Where fees come from and how private holders earn.
- **[Trust model](/docs/trust-model)**: What the team cannot do, and what is still unproven.
- **[Contracts](/docs/contracts)**: The pool's functions, events and errors.
