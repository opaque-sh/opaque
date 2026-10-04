---
title: Threat model
description: What Opaque protects against, and the gaps that are known today.
---

## What it protects

- **Your balance and your payments inside the pool.** An observer cannot see who owns a note, how much it holds, or who paid whom.
- **Your funds from the team.** No admin can move or freeze notes.

## What it does not protect

- **The edges.** Deposits and withdrawals are public.
- **Habits.** Matching amounts and timing, reusing addresses and linking yourself elsewhere. See [Staying private](/docs/staying-private).
- **A small crowd.** Privacy grows with the number of notes. Early on, there are few.
- **Your network.** Your RPC provider sees your requests.

## Known gaps today

| Gap | Status |
| --- | --- |
| No audit | The code is unaudited |
| No generated verifier | The verifier has not been produced or tested end to end |
| No wallet-key binding | Anyone who learns a note key can spend its notes. The binding is planned |
| Proof system is not post-quantum | A future quantum attacker could forge proofs. The hash-based parts are not affected. See [Research](/docs/research) |
| Ciphertexts live on-chain forever | Today they depend on classical key exchange. A hybrid scheme is proposed |
| Fee harvester unaudited | Written and tested against mocks and a real Uniswap v4 pool. It has not run against the live Pons contracts and is not audited |
| A successor can redirect future fees | The harvester's owner can propose a successor that becomes the fee recipient after 24 public hours. Renouncing ownership removes this |
| Pons can redirect the fee recipient | Pons' own takeover process can move a token's creator fee recipient after a delay. The harvester cannot stop it |
| Gas cost | A private exit is expensive and may exceed public bundler limits |

## Reporting

Report a vulnerability through the contact in `SECURITY.md`. A public bounty is planned.
