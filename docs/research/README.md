# Research

Open questions and directions we are exploring for Opaque. None of this is built, audited or promised. The shipped design is in `docs/DESIGN.md`, and the order of work is in `docs/ROADMAP.md`.

Follow this folder to watch the thinking develop. Each topic gets its own note as it matures.

## Directions

### Notes that survive quantum computers
Today's note encryption uses elliptic curves, which a large quantum computer could break. We plan a hybrid key exchange (elliptic curve plus a post-quantum scheme) with a versioned ciphertext format, and a longer path toward a hash-based proof system. See `docs/DESIGN.md` section 11.

### Epoch keys and forward secrecy
Keys that rotate on a fixed schedule, so a leaked key exposes one window instead of everything. Also a way to disclose activity for a date range without revealing the rest.

### Time-bounded anonymity
Whether privacy sets can be organized around fixed windows, and what that would do to linkability over time. Open question: how it fits a shared note tree with nullifiers.

### Private movement between chains
Moving shrouded value across chains without exposing source, destination or amount to a bridge operator. Open question: what a bridge can attest to without learning anything.

### Private swaps
An in-circuit epoch swap, so notes can move between assets without a public link. Reference exit-target design comes first, as in the roadmap.

### Private payments for AI services
Blind-signed tokens bought by spending notes, so a service can be paid without linking the payment to a wallet. Open question: what the service itself can still observe.

### Computing on shrouded balances
Long-term and uncertain: encrypted computation over private state. We list it so the question stays visible, not because there is a design.

## Contributing

Ideas and critiques are welcome. Open an issue with the topic in the title.
