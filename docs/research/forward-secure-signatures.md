# Forward-secure signatures

## Idea

Make spend authority evolve over time. With a forward-secure scheme, each signature commits to a node in a binary key-evolution tree. A key that leaks at time T cannot be used to forge anything from before T. Your past stays yours even if your future leaks.

## Why it matters

Today a stolen spending key exposes every note it can reach, past and future. Forward security limits the damage to what happens after the theft, and combined with key erasure it makes old notes safe from a later compromise.

## Relation to the current design

The pool spends notes with a zero-knowledge proof of a nullifier key, with no ring signature. Forward-secure authority would sit in the note's ownership key: the owner key evolves along a tree, and the circuit proves the current node belongs to the committed root. A ring-signature variant (FSLRS) is the other route, where linkability tags replace nullifiers.

## Open questions

- What does proving tree membership cost inside the circuit?
- How are keys recovered on a new device without breaking forward security?
- Does the extra state make wallet backup harder in practice?
