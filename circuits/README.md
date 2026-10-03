# Circuits

Noir circuit for the Opaque pool. Proving system: UltraHonk (Barretenberg). Not started in this repo yet.

Changes from the v0 circuit:

1. Commitment becomes cm = H(1, stub, assetId, amount). The asset id is private inside the note and public on the transaction.
2. Conservation is enforced per asset. Both input and output notes must carry the transaction's asset id.
3. Fee and exit amount are checked in the asset's own unit (wei for ETH, shares for the flagship).
4. Decision pending: whether to leave hooks for exit-time lineage proofs before the circuit is frozen. See `docs/DESIGN.md`.

Reference numbers from v0: about 83,781 gates, about 73k of them for the secp256k1 signature check.
