# Sealed batch swaps

## Problem

A swap from a shrouded balance reveals the pair, the size and the time. A single exit target that swaps and pays a fresh address hides the recipient but not the trade, and a lone swap is easy to match to its source.

## Approach

Batch swaps in the style of Penumbra's ZSwap:

1. Users submit swap intents whose inputs are notes. The intents are encrypted.
2. Per block or epoch, the flows for each pair are aggregated. Only the net totals per pair become public.
3. One public swap executes the net flow against an AMM at a uniform price.
4. Each user claims the output for their intent with a proof, in proportion to the batch result, as a new note.

Individual trades are hidden inside the aggregate, and every trade in the batch gets the same price, which removes ordering-based extraction between participants.

## The hard part is aggregation

Summing encrypted amounts needs either an additively homomorphic encryption with a threshold decryption committee, or a trusted party, or multiparty computation. Penumbra uses its validator set. The pool has no validators and no admin, so the committee must be a separate, replaceable, explicitly trusted component, or the aggregation must move into a proof system.

## Relation to the current design

The pool holds a single asset today. Swapping inside the shrouded domain needs a multi-asset pool version. The commitment already carries an asset id for this reason. A simpler first version is an exit target that swaps and pays a fresh address, which is public trade, unlinked recipient.

## Open questions

- Who holds the decryption key, and what happens if they go offline or collude?
- Can partial fills and limit prices be supported without leaking them?
- How large must batches be for the aggregate to hide anything, and what do early low-volume batches reveal?

## References

- Penumbra protocol specification, ZSwap.
