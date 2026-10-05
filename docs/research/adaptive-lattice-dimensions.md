# Adaptive security parameters

## Idea

Let proof and commitment strength scale with the value at stake. Low-value transfers use compact parameters for fast proofs and small calldata. High-value shrouds use higher-dimension parameters. The note tree stores commitments to parameter epochs, so the system can migrate to stronger parameters over time without revealing which notes use which tier.

## Why it matters

A single security level is either too heavy for small transfers or too light for large ones. A migration path matters most for post-quantum parameters, which are still being tuned.

## Open questions

- Tiers split the anonymity set. If only large shrouds use the strong tier, that tier is small and easy to correlate. How do tiers share a crowd?
- Who decides when parameters change? The pool has no admin, so the trigger must be a rule fixed in the contract, not a judgement call.
- Does the circuit have to support several parameter sets at once, and what does that do to proof size and verification cost?
