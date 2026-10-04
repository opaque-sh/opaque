---
title: Fees
description: Where fees come from, where they go, and what is not decided yet.
---

> [!WARNING]
> **Not final**
>
> The holder share and the fee levels are not set. Any number shown anywhere is illustrative. They will be fixed before launch and then cannot change.

## Sources

| Source | Where it goes | Status |
| --- | --- | --- |
| Creator fee on every $OPA trade on Pons, on the curve and in its pool | Fee harvester, then mostly to buy $OPA for the vault, the rest to the team | Harvester not built |
| Flat unshield fee, paid in $OPA | Stays in the pool as backing, so it goes to everyone still shielded | In the contract |
| Shield | No fee | In the contract |
| Relayer fee | Whoever submits the transaction | In the contract, optional |

The pool itself has no fee recipient. Trade fees reach the vault only through the harvester, which buys $OPA and donates it. The harvester is not built yet.

## How private holders earn

A donation adds $OPA to the vault's backing without minting shares, so every $OPA note's shares are worth more. The pool prices shares like this:

```
shares = amount * (units + 1e6) / (backing + 1)
tokens = shares * (backing + 1) / (units + 1e6)
```

Anyone can donate to the vault. The virtual offset makes the classic share-inflation attack uneconomic.

## Who does not earn

Public $OPA does not earn. It gets price support from buybacks and from a float that shrinks as more $OPA is shielded. Yield comes only from fees. It can be zero.

## Unshield fee is flat

An exit fee that grew with a note's age would reveal the note's age. Opaque uses a flat exit fee so it reveals nothing. It is a fixed amount of $OPA set at deployment, so a very small exit can be smaller than the fee and is rejected.
