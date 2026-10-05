# Research

Where Opaque is heading beyond the live pool. Each note describes an idea, how it relates to the current design, and what is still open. These are research directions. The shipped design is in `docs/DESIGN.md`, and the order of work is in `docs/ROADMAP.md`.

| Note | Question it asks |
| --- | --- |
| [Quantum-safe notes](quantum-safe-notes.md) | Can notes and proofs rest on lattice and hash assumptions instead of elliptic curves? |
| [Forward-secure signatures](forward-secure-signatures.md) | Can spend authority evolve so that a leaked key cannot touch the past? |
| [Healing privacy](healing-privacy.md) | Can linkability decay over time, so exposure has a half-life? |
| [Stealth channels](stealth-channels.md) | Can payment channels open and settle without revealing who or how much? |
| [Adaptive security parameters](adaptive-lattice-dimensions.md) | Can proof strength scale with the value at stake without splitting the crowd? |
| [Computing on shrouded balances](shrouded-computation.md) | Can contracts run on encrypted state? |
| [Private cross-chain movement](cross-chain.md) | Can value move between chains without a bridge operator seeing it? |

## How to read these notes

Terms used throughout:

- **Note:** a private record of value inside the pool.
- **Nullifier:** the tag revealed when a note is spent. It stops double spends. In ring-signature designs the equivalent is a key image or linkability tag.
- **FSLRS:** forward-secure linkable ring signature. A ring signature hides which member of a group signed, linkability lets the system detect two signatures from the same key, and forward security means a key stolen today cannot forge signatures from before the theft.

## Contributing

Ideas and critiques are welcome. Open an issue with the topic in the title.
