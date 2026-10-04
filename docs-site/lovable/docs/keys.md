---
title: Keys
description: The keys behind a private note, and what is not built yet.
---

## What exists now

A note is owned through a secret nullifier key `nk`. The owner key is `opk = H(3, nk)`. Anyone with `nk` can spend the owner's notes.

Each note also carries an encrypted copy for its recipient, so wallets can find and read their own notes.

## What is planned

> [!WARNING]
> **Not built**
>
> These pieces are designed and not implemented.

- **Wallet-key binding.** A spend would be tied to a wallet signature (an EIP-712 message), so your note keys come from one wallet signature and you have nothing extra to back up. The earlier prototype did this, and the check is not yet in the new circuit.
- **A key registry.** So people can send to your address without asking you for a key.
- **Disclosure keys.** A receipt for one payment, a read-only view of an account, and a signed report for a date range, so you can prove what you choose to prove.

## Longer-term

Note ciphertexts stay on-chain forever, so they need to hold up against future attacks. See [Research](/docs/research).
