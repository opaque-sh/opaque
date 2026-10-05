# Private cross-chain movement

## Idea

Use signatures with linkability as a bridge attestation layer. A set of notaries signs cross-chain messages. Linkability stops the same deposit being claimed twice on different chains, and forward secrecy means compromising a notary later cannot forge past bridge proofs. Assets move between chains without the bridge operator seeing source, destination or amount.

## Why it matters

A shrouded pool on one chain is only as useful as the places value can go. A private bridge lets shrouded value reach other chains without surfacing in a public bridge contract.

## Relation to the current design

The pool is single-chain and single-asset. A cross-chain version would be a separate pool or exit target, and the shared-tree design leaves room for it.

## Open questions

- A notary set is a trust assumption. How small can that trust be made, and can it be replaced by verifying a proof of the source chain's state?
- Amounts are visible at a bridge's edges. How much privacy survives at the entry and exit?
- What happens to in-flight transfers if the notary set rotates?
