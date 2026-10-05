# Computing on shrouded balances

## Idea

Run contract logic on encrypted state. Authority is proven without identity (a forward-secure signature), and the validity of a state transition is evaluated in the encrypted domain using lattice-based fully homomorphic encryption. Execution leaves no traceable signature pattern, and forward secrecy protects past states if keys leak later.

## Why it matters

It would allow private versions of things that currently need public state: private order books, private auctions, private lending against shrouded collateral.

## Status

Long-term and uncertain. Fully homomorphic encryption is still orders of magnitude too slow for on-chain verification, and there is no design here yet. It is listed so the question stays visible and so nearer-term work (exit targets, private swaps) does not close the door on it.

## Open questions

- Which parts can run off-chain with a succinct proof of correct execution, so the chain verifies a proof and not the computation?
- How is decryption authority shared, so no single party can read the state?
- What is the smallest useful private contract, and can it be built with today's tools instead?
