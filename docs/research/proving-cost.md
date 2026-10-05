# Proving cost and proof systems

## Problem

The pool verifies one UltraHonk proof per transaction, about 16 KB, and the browser builds it single-threaded. Both costs shape who can use the product. Calldata and verification gas fall on the user, and proving time falls on the device.

## Directions

1. **Batch aggregation.** A relayer proves a batch of unshrouds inside one outer proof, so verification gas is paid once per batch. Aggregation must not reveal which proofs came from the same user, so batches need many participants and careful timing.
2. **Hash-based verification.** Transparent, hash-based proof systems rely on hash assumptions, not pairings, which matters for the quantum-safe track. WHIR is a recent proximity test for Reed-Solomon codes designed for fast verification. Whether it makes on-chain verification cheaper than UltraHonk must be measured on the real circuit before any claim.
3. **Smaller circuits.** The Merkle path of 24 levels is repeated for each input. Shorter paths through epoch subtrees, or incremental paths supplied as witness data, reduce constraint count.
4. **Faster in-browser proving.** Multithreading needs cross-origin isolation headers, which the app avoids for compatibility with wallets. WebGPU and WASM SIMD are alternatives, as is proving in a worker process.
5. **Folding and recursion** for sequences of notes owned by one user, so repeated activity amortises.

## Constraints

Changing the proof system means a new verifier and a new pool version, since the pool is immutable. Notes migrate one owner at a time, which splits the crowd for a while. That cost has to be weighed against the gain.

## Open questions

- What is the verification gas and calldata of a candidate system on this circuit, measured?
- Is batch aggregation compatible with the no-admin rule, or does it need a coordinator?
- At what pool size do these optimisations become necessary?

## References

- Arnon, Chiesa, Fenzi, Yogev, "WHIR: Reed-Solomon Proximity Testing with Super-Fast Verification", 2024.
