---
title: Shroud and unshroud
description: What goes in, what comes out, and what is public at each step.
---

## What is public

| Step | Public | Hidden |
| --- | --- | --- |
| Shroud | Your address, the amount | Nothing about the note's later use |
| Inside the pool | That a transaction happened, the nullifiers and commitments | Who owns the notes, the amounts, who pays whom |
| Unshroud (exit) | The recipient, the amount | Which notes it came from |

Opaque hides what happens between a deposit and a withdrawal. It does not hide the deposit or the withdrawal.

## Shrouding

Approve the pool, then shroud $OPA. There is no shroud fee. The pool mints shares at the current share price. The pool rejects tokens that take a fee on transfer, because the amounts would not add up. ETH and other tokens cannot be shrouded.

A note holds at most 120 bits of value.

## Deposit caps

The pool has a deposit cap on total $OPA that starts low and rises on a fixed schedule: an initial cap, a step amount, a step interval and a ceiling. The schedule is set at deployment and nobody can change it. The numbers are not decided yet.

## Pausing

The guardian can pause new shrouds. Spends, exits and donations always work.

## Unshrouding

An exit is part of a private transaction. It names a recipient and an amount in the proof, so nobody who relays it can change them. Every exit pays a small percentage of the amount in $OPA, fixed at deployment. It stays in the pool for the holders who remain. An optional relayer fee can be paid to whoever submits the transaction.

Exits to a contract that acts on the funds (a swap, a payment gateway) are planned and not live. See [Integrations](/docs/integrations).
