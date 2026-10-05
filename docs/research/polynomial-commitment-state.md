# Polynomial-commitment note sets

## Problem

Merkle trees give logarithmic membership proofs but make state grow as a tree, and the proof cost in a circuit is a hash per level. At depth 24 that is 24 hash evaluations per input note.

## Mechanism

Commit to the note set as a polynomial `P` with `P(i) = c_i`, where `c_i` is the commitment to note `i`. A membership proof is an opening: a witness `pi` that `P(i) = c`, checked by a pairing equation for KZG, or by a FRI check for a hash-based scheme. In a circuit, inside a ZK proof, the opened index and value stay private, so there are no sibling hashes to reveal because there are none to compute.

Appending a note to a KZG-committed set is a single group operation if the commitment uses a Lagrange basis over a fixed domain: add `c_i` times the precomputed Lagrange commitment for position `i`. The on-chain state is one group element.

## Trade-offs

- A KZG commitment needs a structured reference string whose size bounds the number of notes. Opaque already uses a universal SRS, so this does not add a new class of assumption, but capacity is fixed per setup, and elliptic curve pairings are not quantum safe.
- A hash-based variant (FRI) removes the pairing and the SRS and is the same family as the quantum-safe track. Its proofs are larger.
- The note's opening proof must stay valid as new notes are appended. With Lagrange-basis updates the witness for old positions changes when the commitment changes, so wallets maintain witnesses incrementally or re-derive them from public data.
- The benefit to claim is circuit cost and constant on-chain state, to be measured against depth-24 Poseidon2 paths. It is not an improvement in anonymity, which comes from the set size and the exit policy.

## Open questions

- Does a pairing check inside the UltraHonk circuit cost less than 24 Poseidon2 evaluations? If not, the benefit disappears.
- Can witnesses be refreshed by a batched, untrusted aggregator so wallets stay light?
