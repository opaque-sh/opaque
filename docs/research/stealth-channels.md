# Stealth channels

## Idea

Payment channels where the opening transaction proves membership in a set without revealing which member opened it. Channel capacity and the counterparty stay hidden. Double-spend prevention comes from linkability on the authorising signature, with no graph analysis possible on the channel topology.

## Why it matters

Private sending between shrouded balances is on the roadmap, but each transfer is an on-chain action. Channels would let two parties exchange many private payments with a small number of on-chain events, which matters for recurring payments such as paying for AI usage.

## Relation to the current design

Channels would be a layer on top of notes: opening locks a note into a channel, and closing returns balances as new notes. The pool itself does not change.

## Open questions

- What does a channel reveal about its size and lifetime when it opens and closes?
- How are disputes and abandoned channels settled without an admin?
- Can a channel open and close inside the existing two-input, two-output circuit, or does it need a new one?
