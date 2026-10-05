# Healing privacy

## Idea

Time-bounded anonymity sets. Activity is grouped into epochs (for example a window of blocks). Linkability tags decay: after N epochs, a tag can no longer be matched against earlier ones from the same signer. Exposure gets a half-life, so a past slip does not become a permanent record.

## Why it matters

In most privacy systems a single deanonymising mistake is permanent. If linkability fades, a user who exposed a link once can recover privacy by waiting and rolling their notes forward.

## Relation to the current design

The pool uses nullifiers, which must stay checkable forever to stop double spends. Decaying linkability means old tags stop protecting against double spends, so every note would need a bounded lifetime: it has to be rolled into the current epoch before its tags expire. Epoch keys, already on the roadmap, are the first step: they limit damage and allow date-range disclosure without any change to spend rules.

## Open questions

- How does the pool stop a double spend after a tag has decayed?
- What does a mandatory roll-forward cost users in gas and attention?
- Does a fixed epoch length leak timing information?
