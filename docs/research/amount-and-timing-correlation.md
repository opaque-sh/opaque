# Amount and timing correlation

## Problem

Shroud and unshroud amounts are public. In a pool with few users, the cheapest attack on privacy is not cryptographic. It is matching: a shroud of 1,000 at time t and an exit of about 997 at time t + a few minutes are almost certainly the same person. Measurement work on Tornado Cash found that heuristics of this kind (amount, timing, address reuse, gas behaviour) link a large share of deposits to withdrawals, even though the proofs themselves are sound. Opaque's variable amounts make the amount signal stronger than a fixed-denomination mixer, not weaker.

The exit fee and the changing share price blur the match slightly, since an exit of a full note differs from the deposit by the fee and by the yield accrued. That is a small, predictable offset an adversary can model.

## Directions

1. **Wallet-side exit policy.** The wallet never exits the exact balance. It splits an exit into several smaller amounts drawn from common values, spaced by randomised delays, and leaves the remainder shrouded. The 2-input, 2-output circuit already supports change notes, so no contract change is needed.
2. **Prefer in-pool movement.** Private sending keeps value inside the pool, where only the owner changes. Exits then become rare and low-signal.
3. **A live linkage score.** The wallet computes, for a planned exit, how many shrouds in a time window are consistent with it, and shows the effective anonymity set as an entropy, not a headcount. If it is small, the wallet advises waiting.
4. **An adversary simulator.** A tool in the repo that replays on-chain events and runs published linking heuristics against them, so the project can measure its own privacy instead of asserting it.

## Open questions

- What delay distribution gives the most protection for the least waiting, and does it hold up when many users follow the same default?
- Does a shared default policy create its own fingerprint?
- Would a second pool with fixed denominations be worth having for users who want the strongest matching resistance?

## References

- Wang et al., "On How Zero-Knowledge Proof Blockchain Mixers Improve, and Worsen User Privacy", WWW 2023: https://arxiv.org/pdf/2201.09035
