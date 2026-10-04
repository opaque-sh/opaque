---
title: Gas and ERC-4337
description: What a private transaction costs, and the plan for paying gas without a public wallet.
---

> [!WARNING]
> **Planned**
>
> Gasless private transactions depend on an ERC-4337 account path that is not ported into Opaque yet.

## Why gas matters for privacy

If your public wallet pays gas for a private transaction, your address shows up next to it. The plan is for the pool to act as an ERC-4337 account, so a bundler submits the transaction and the network fee is paid out of the notes being spent, not from your wallet.

## Measured so far

| Item | Gas |
| --- | --- |
| One tree insert | about 1 million |
| A two-note transaction, before proof verification | about 2 million |
| A private exit in the earlier prototype, end to end | 4.7 to 5.2 million |

The last figure may exceed public bundler limits. The tree insert cost is being reduced before launch. Proof verification cost for the new circuit is not measured yet.

## Open

- Whether a private transaction fits under public bundler gas limits.
- How a bundler is paid out of a note without revealing which note.
