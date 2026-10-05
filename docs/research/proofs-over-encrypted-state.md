# Proofs over homomorphically encrypted state

## Problem

Private DeFi wants to compute on balances nobody sees. Fully homomorphic evaluation is slow, and multiparty computation needs parties online together. Shielded pools avoid the issue by moving all logic into the owner's wallet, but shared state (a pool balance, an order book) still has to be computed on by someone.

## Mechanism

Combine leveled homomorphic encryption with a proof of well-formedness. A user holds a BFV ciphertext of a balance. To spend, they produce:

1. A ciphertext of the new balance, computed homomorphically as `Enc(balance) - Enc(spend)`.
2. A proof that the new ciphertext was computed correctly from the old one, that the plaintext is non-negative (a range proof on the committed amount), and that the sender controls the key.

Validators check the proof and never decrypt. Only the key holder sees plaintext.

## Constraints that shape the design

- Proving polynomial arithmetic over a ring inside a SNARK is expensive. Matching the BFV plaintext modulus to the proof field avoids a non-native arithmetic penalty, and the circuit must still verify ring multiplications and noise growth. For a single subtraction, no relinearisation is needed, which keeps the circuit small.
- Additive operations are cheap. Multiplication, which an order-matching engine needs, consumes noise budget and pushes the design toward a bootstrapping-free, bounded-depth use.
- The speed-up over full FHE comes from not evaluating anything homomorphically on-chain. The user (or a prover) does the work and the chain checks a proof, so the cost is proving time, which should be measured on a real implementation before any number is quoted.

## Fit with Opaque

For plain balances the note model already wins: it is simpler and cheaper. This approach earns its place only for shared, mutable aggregates, such as a private pool-wide counter or reserve, where a single owner does not exist.

## Open questions

- Which aggregate operations does a private AMM need, and are they additions only?
- Can the key be threshold shared across a committee so that a single user is not the only party able to read an aggregate?
