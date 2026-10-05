# Coarse exit amounts

## Problem

Variable amounts are what make the pool useful, and also what make exits fingerprintable. An exit of 12,347.81 $OPA is unique in the world. Anyone who saw a shroud of about 12,350 minutes earlier has the link, whatever the proof hides.

## Proposed design

Constrain the public exit amount inside the circuit to a coarse grid, and send the remainder back into the pool as a change note.

- The exit amount must have the form `m * 10^k` with `m` in a small range such as 1..99 (two significant digits).
- The circuit proves `exit_amount = m * 10^k`, range checks `m` and `k`, and proves the change note carries `input_total - exit_amount - fee`.
- A user exiting 12,347.81 exits 12,000 and keeps 347.81 shrouded, or exits 12,000 and then 340 in a second transaction.

Both cases leave the exact balance inside the pool. Observers see exits drawn from a few hundred common values instead of a continuum, so the set of shrouds consistent with an exit is far larger.

## Why it helps beyond splitting

Wallet-side splitting (see amount and timing correlation) is a convention, and conventions fail when one wallet deviates. Enforcing the grid in the circuit makes the anonymity set a protocol property. No wallet, including a hostile or buggy one, can exit an identifying amount.

## Cost

Roughly one extra range check and a multiplication by a power of ten selected from a small table, a few dozen constraints. Dust below the smallest grid step stays shrouded until it is combined with more value, which is a feature for privacy and a mild annoyance for users who want to sweep to zero. A "sweep" mode that exits exact amounts, clearly marked as public-fingerprint, can exist for people who prefer convenience.

## Open questions

- What grid minimises the number of transactions a typical user needs while keeping the set large? Two significant digits is a starting point to be tuned against the real exit distribution.
- Does the grid itself become a fingerprint if only some users follow it? Enforcement in the circuit removes the "some" problem for new pools; a migration path covers the live one.
