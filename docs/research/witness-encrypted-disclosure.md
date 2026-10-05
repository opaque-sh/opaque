# Witness-encrypted conditional disclosure

## Problem

Privacy today is binary: a note is shielded or it is not. A user cannot say "reveal this if a governance audit passes" without a trusted party holding a key and deciding when to use it.

## Mechanism

Witness encryption encrypts a message to a statement instead of a key. Anyone holding a valid witness for the statement can decrypt, and nobody else can. If the statement is "there is a quorum of signatures from the audit committee over this audit request", then:

- A user encrypts a disclosure key for their notes to that statement and posts the ciphertext.
- The committee publishes its approval on-chain when, and only if, it decides to audit.
- Anyone can assemble the witness from the public approval and decrypt. No party holds a standing key that can be coerced or leaked.

## What is buildable

- **Time locks and threshold conditions** can be done today without general witness encryption. Time-lock puzzles or a threshold-decryption network that releases a share only when an on-chain predicate holds give the same user-visible behaviour for those two predicates.
- **General NP statements** need real witness encryption. Known constructions rest on indistinguishability obfuscation or on newer lattice assumptions and are not practical. The design keeps the interface (`encrypt(statement, message)`) fixed so the backing scheme can be swapped as better ones appear.
- The secrecy guarantee is computational, as for all of these schemes. It holds as long as the underlying assumption does.

## Fit with Opaque

This is the cryptographic version of selective disclosure: a pre-committed, user-opted disclosure that fires on a public event. It composes with association sets, which prove a property now, whereas this reveals data later.

## Open questions

- Which predicates matter enough to justify a bespoke construction (threshold approval, time, a signed court order)?
- How does the disclosure key bind to exactly the notes the user intends, and not more? A per-note key derived from the viewing key is the starting point.
