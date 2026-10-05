# Quantum-safe notes

## Idea

Replace the elliptic-curve assumptions in notes and note encryption with lattice and hash-based ones, so a future quantum computer does not break privacy or spending.

## Two tracks

**Near term, concrete.** Note ciphertexts currently use X25519 key exchange. The plan is a hybrid exchange (X25519 plus the ML-KEM standard) with a versioned ciphertext format. An attacker who records ciphertexts today then needs to break both. This needs no change to the pool.

**Longer term, research.** Commitments built on Module-LWE hardness, with a proof system that does not rely on elliptic curves (hash-based proofs, or lattice-based zero-knowledge). The goal is notes whose security rests only on lattice and hash assumptions.

## Relation to the current design

The live pool uses Poseidon2 commitments and an UltraHonk proof, which depends on elliptic-curve pairings. The pool is immutable, so the route is a new versioned pool that notes can migrate into one owner at a time. See `docs/DESIGN.md` section 11.

## Open questions

- Which post-quantum proof system gives proofs small enough to verify on-chain at reasonable gas?
- How large are lattice commitments, and what does that do to the cost of a shroud?
- How does a migration between pool versions avoid splitting the anonymity set?
