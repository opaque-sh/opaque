# Revocable anonymous credentials with epochs

## Problem

Anonymous credentials, such as "verified human" or "passed compliance", have a conflict at their core. If a credential can be revoked, the revocation check must test the credential's identity, and testing it can link the holder across uses. Sybil resistance wants one credential per person. Privacy wants uses to be unlinkable.

## Mechanism

- The issuer signs a credential with BBS+ (or a comparable pairing-based scheme) over attributes, including a hidden credential id and a validity epoch.
- The issuer maintains a revocation accumulator over revoked ids. A holder proves in zero knowledge that: the signature is valid, the id is not in the accumulator (a non-membership witness), and the current epoch is inside the validity window.
- Credentials expire every N epochs. Renewal re-issues a fresh blinded credential after the issuer re-checks revocation status, so the accumulator stays small and holders update their witness once per epoch rather than per use.
- A per-epoch nullifier derived from the credential id and the epoch tag gives Sybil resistance within an epoch: one credential can act once per context per epoch, and uses in different epochs are unlinkable.

## Accumulator choice

Pairing-based accumulators have constant-size witnesses and support non-membership proofs, which is what revocation needs. The witness update cost when the revoked set changes is the practical limit, and it is why epoch renewal is part of the design rather than an add-on.

## Fit with Opaque

This is the credential layer behind association sets: a pool lane that requires "not revoked this epoch" without learning who the user is. Revocation takes effect at the next epoch boundary, so a revoked party is blocked from new lane entries, while past activity stays unlinked from the revoked identity.

## Open questions

- What is the right epoch length, given that revocation latency equals one epoch?
- Who is the issuer, and how is the issuer itself constrained from linking by timing or from issuing bad credentials? Threshold issuance across independent parties reduces single-issuer trust.
