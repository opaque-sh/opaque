---
title: Integrations
description: Exit targets, and what is not wired in yet.
---

> [!WARNING]
> **Not live**
>
> Exit targets are designed and not enabled. Today, a transaction with non-empty `ext.data` reverts with `ExitTargetsNotSupported`, and every exit is a plain transfer to the recipient.

## The idea

An exit target is a contract that receives value from a private exit and acts on it: a swap router, a payment gateway, a move into another vault. The note owner names the target in the proof, so a relayer cannot redirect the funds, and the app shows a manifest of what the target will do before you sign.

## The interface

```solidity
interface IExitTarget {
    function onPrivateExit(address asset, uint256 amount, address recipient, bytes calldata data) external;
}
```

The target may pull up to `amount` of `asset`, which the pool has just approved or sent. Whatever the target leaves, or everything if it reverts, goes to `recipient` in the same asset.

## Open questions

- Who vets targets. The plan is an events-only registry with a "verified" badge in the app. The registry has no power over the pool.

## What this unlocks

Private swaps and private payments are exits to a target, not changes to the pool. This is how the roadmap items for private AI payments and the swap hub are meant to work. See [Roadmap](/docs/roadmap).
