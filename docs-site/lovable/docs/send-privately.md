---
title: Send privately
description: How a private transfer works, and what is still missing.
---

> [!WARNING]
> **Planned**
>
> The pool contract and the circuit support private transfers. The app and the key registry do not exist yet.

## What a private transfer is

One transaction spends up to two notes of one asset and creates two new notes. If the exit amount is zero, nothing leaves the pool: the value just moves from your notes to new notes, one of which can belong to someone else.

The chain sees two nullifiers (the spent notes, unlinkable to their commitments), two new commitments, and two encrypted blobs. It does not see the sender, the recipient or the amount.

## How the recipient finds the note

The new note comes with an encrypted copy addressed to the recipient's key. Their wallet scans the encrypted copies and decrypts the ones meant for it. To send to someone, you need their receiving key. A registry of receiving keys is planned.

## Proof of payment

A private send can come with a proof of payment: a link that shows a recipient was paid an amount, and nothing about the sender. This depends on disclosure keys and is not built. See [Keys](/docs/keys).
