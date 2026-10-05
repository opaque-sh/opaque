# Epoch-batched exits

## Problem

Even with coarse amounts, an exit lands in a specific block. Timing correlation (shroud at t, exit at t plus a few minutes) is the oldest deanonymisation trick in mixer analysis, and wallet-side random delays only help as far as users apply them.

## Proposed design

Make timing a protocol property the same way the amount grid is.

- Exits are submitted as normal proofs, but they carry an `epoch` public input. The contract queues the withdrawal and releases it at the first block of that epoch, for example every N blocks.
- All exits in an epoch pay out in the same transaction block, so the on-chain order and block of payout carry no information about when each proof was generated.
- The proof binds the epoch, so a queued exit cannot be redirected, and the nullifier is spent at submission, so it cannot be double queued.

Observers see a set of proofs enter a queue and then a batch of payouts. The submission time is still visible, but the payout time is the same for every exit in the epoch and the epoch is long enough that submission time tells nothing about when the underlying shroud happened.

## Trade-offs

- Exit latency becomes up to one epoch. For an asset used as a store of value that is cheap. For urgent exits a "fast lane" with no batching exists and is visible as such.
- The queue holds funds in the pool's custody for a short window, which must be accounted for in backing so it cannot be double counted by the deposit cap.
- Epoch length trades privacy against convenience. The note proposes measuring the real inter-arrival distribution of exits before picking a number.

## Open questions

- Can the epoch be chosen adaptively so that every epoch contains at least k exits, otherwise rolling into the next one?
- How does an epoch queue interact with relayers, which also introduce delay? The two can share a window.
