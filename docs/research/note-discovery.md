# Note discovery and scanning

## Problem

A wallet finds its notes by downloading every note event and trying to decrypt each ciphertext. That is private, because the node learns nothing about which notes are yours, but it costs bandwidth and CPU that grow with the whole pool. A light wallet that asks a server "which events are mine?" leaks exactly that.

## Directions

1. **View tags.** The sender adds a one-byte tag derived from the shared secret between the sender's ephemeral key and the recipient's view key. The recipient computes the tag first and skips about 255 of every 256 trial decryptions. The tag reveals nothing without the view key. This can be done entirely client-side by placing the tag in the ciphertext prefix, with no contract or circuit change. ERC-5564 uses the same idea for stealth addresses.
2. **Fuzzy message detection.** The wallet hands a detection key to an untrusted server. The server returns a superset of the events that may be for the wallet, with a false-positive rate the wallet chooses. A higher rate hides more but costs more bandwidth. The server learns only a probabilistic statement about interest.
3. **Oblivious message retrieval.** The server runs a homomorphic computation over all events and returns a single compact digest from which the wallet can recover its notes. The server learns nothing. The price is heavy server computation.
4. **Epoch checkpoints.** Wallets store a signed or contract-attested summary of the tree at epoch boundaries, so a new device scans only recent events.

## Relation to the current design

Event scanning today uses localStorage caching and a search over `nextIndex` to find blocks that added leaves. View tags would cut CPU on top of that and are the cheapest first step. The cryptographic options matter once the pool is large enough that downloading everything is impractical.

## Open questions

- What tag length balances speed against how much a tag narrows the set of possible recipients?
- Can detection keys be rotated per epoch to limit what a server learns over time?
- How are scanning services paid for without becoming a metadata collector?

## References

- Beck, Len, Miers, Green, "Fuzzy Message Detection", ACM CCS 2021.
- Liu, Tromer, "Oblivious Message Retrieval", CRYPTO 2022.
- ERC-5564, Stealth Addresses.
