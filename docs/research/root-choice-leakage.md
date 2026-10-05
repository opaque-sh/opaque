# Root-choice leakage

## Problem

Every unshroud proof is made against a Merkle root, and that root is a public input. The contract accepts any of the last 64 roots. The choice looks harmless, but it is a signal: proving against root R tells everyone the spent note was inserted before R. If a wallet always proves against the tightest root that contains its note, the root is a timestamp for the shroud, accurate to a few blocks. That collapses the anonymity set from "every note in the tree" to "every note inserted before R and after the previous plausible root."

This leak sits outside the circuit. The proof is zero-knowledge and the leak is still there, because the verifier is told which tree the note lives in.

## Proposed design

1. **Newest-root rule.** Wallets prove against the most recent root they have seen, never the earliest one that contains the note. A newest root says nothing about when the note arrived, only that it arrived at some point before now.
2. **Root-age floor in the wallet.** The wallet refuses to prove against a root younger than N blocks, so every exit in a window shares a small set of roots and no one exit stands out by freshness.
3. **Stale-root tolerance as a parameter.** The 64-root history exists so proofs survive concurrent insertions. The policy treats history depth as a latency buffer, not as a choice the wallet should exercise.
4. **Observed-root histogram.** The adversary simulator records, per exit, how far behind the head its root was. A wallet population that is not centred on "near head" is leaking, and the simulator flags it.

## Why it matters

Most privacy analysis stops at the proof. Metadata about which public inputs a wallet picks is a second channel, and it is cheap to close at the wallet layer. This note is the first of a set about leaks that live between the circuit and the chain.

## Open questions

- Near-head proofs race against new insertions. How much slack does a busy pool need so that newest-root proving does not cause reverts?
- Can the contract expose a single canonical "current prove root" per block to remove the choice entirely?
