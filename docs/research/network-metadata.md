# Network metadata and private RPC

## Problem

Proofs hide what happens on-chain. They do nothing about what the network layer sees. The RPC provider sees the IP address, the wallet's account, every query and the timing. When a user submits an unshroud, the provider sees the recipient address and the IP in the same request. The sequencer sees submitted transactions as well.

## Rules for the wallet

- **No note-specific queries.** Asking an RPC "is this nullifier spent?" tells it which nullifiers belong to this IP before they ever appear on-chain. The wallet derives spent status from bulk log downloads and never asks about individual notes.
- **Bulk reads only.** Download ranges of events, never lookups keyed by anything derived from the user's keys.

## Directions

1. **Oblivious HTTP for JSON-RPC.** Requests go through a relay that sees the IP but not the content, to a gateway that sees the content but not the IP. Neither alone can link a user to a query. Standardised as RFC 9458.
2. **Private information retrieval for reads.** Single-server PIR schemes let a client read an entry from a public database without the server learning which entry. Fixed-structure data such as tree levels and nullifier ranges fit this well. Throughput of recent schemes makes it plausible for small, hot databases.
3. **Mixnet or Tor transport** for transaction submission, with the relayer in the path.
4. **The relayer as the submission path.** A relayer that receives the proof over an oblivious channel and submits it removes the user's IP from the on-chain picture. It still sees the recipient, so relayer choice and hop count matter.

## Open questions

- Which of these can run in a browser without an install?
- How much does PIR cost for a database that changes every block?
- Can the app ship with a default private transport, so the safe path is the one users get without choosing?

## References

- RFC 9458, Oblivious HTTP.
- Menon, Wu, "Spiral: Fast, High-Rate Single-Server PIR via FHE Composition", IEEE S&P 2022.
