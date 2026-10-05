# Oblivious contract storage

## Problem

Encrypting values does not hide which values are touched. If a wallet always reads slot 42 before it transfers, every observer learns that slot 42 is its balance. On a public chain every storage access is visible, so access patterns are a first-class leak, separate from the data.

## Mechanism

Store state as a binary tree of encrypted blocks, as in Path ORAM or Circuit ORAM. A logical read or write of block `a` works like this:

1. Look up the leaf `l` the block is currently assigned to (held in a position map).
2. Read the root-to-leaf path for `l`, decrypt, and find the block.
3. Assign the block a fresh uniformly random leaf, apply the update, and re-encrypt every block on the path with fresh randomness.
4. Write the path back.

The observer sees a path to a uniformly random leaf and a rewrite of every block on it. The sequence of paths is independent of the logical addresses.

## On-chain construction

- Tree integrity uses Poseidon2 hashes, matching the pool's hash.
- A circuit proves path consistency against the old root, correct re-encryption of each block, and the new root. The chain stores only the root and verifies one proof per batch.
- The position map is the hard part. Kept on-chain in the clear it leaks the assignment. It has to live inside the encrypted state recursively (a smaller ORAM holding the map of the larger one) or client-side, which fits single-owner state such as a user's own account tree.
- Batching many operations in one proof amortises the verification cost. Proof size does not grow with the number of operations, circuit size does.

## Cost

Bandwidth is O(log N) blocks per access, and the circuit does O(log N) hash and cipher checks per access. Storage is a constant factor over the logical size. The honest comparison is against the pool today, where the access pattern is already hidden because notes are only ever appended and nullifiers are random-looking. ORAM matters when state is mutable and shared, for example private AMM reserves where the direction of a trade must not be inferred from which slot changed.

## Open questions

- Is a recursive position map affordable inside a circuit, or does the design only fit owner-held state?
- Which cipher is cheapest to prove for block re-encryption? Poseidon2 in sponge mode is the obvious candidate.
