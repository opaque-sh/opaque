# Churn transactions

## Problem

An anonymity set is not only about how many notes exist. It is about how many of them could plausibly be the one an attacker is looking for. A note that has sat untouched since insertion has a precisely known age, and age is a feature. Most deposits eventually exit, so old unspent notes are a shrinking, increasingly identifiable group.

## Proposed design

Add a cheap in-pool transaction type whose only job is to refresh a note.

- A churn transaction spends one or two notes and creates fresh notes of the same total to the same owner, with new commitments, new randomness and new nullifiers.
- It is the existing 2-in 2-out circuit with no public amount change, so there is no new proof system or verifier.
- Wallets schedule churns at random intervals in the background. Each churn resets the visible age of the note to the age of the churn.
- A shared fee-funded churn subsidy is possible: a small slice of the exit-fee backing pays relayers for submitting churns, so privacy maintenance is not gated on the user holding gas.

## What it buys

- Age-of-note signals fade. The adversary can no longer assume an old note is a long-term holder, or that a recent note is a fresh depositor.
- Notes become exchangeable between users with different time horizons, which raises the effective anonymity set for exits.
- The cover traffic is real activity, not dummy data, so it costs the chain nothing it was not already designed to handle.

## Open questions

- At what churn rate does the pool's insertion rate saturate the tree? Depth 24 holds about 16.7 million leaves, so churn needs a rate cap or a batched form that creates more than one note per transaction at amortised cost.
- Does subsidised churn attract spam, and what is the right rate limit (per nullifier epoch, per fee payment, or per proof of age)?
