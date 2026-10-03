# Circuits

Noir circuit for the Opaque pool. Proving system: UltraHonk (Barretenberg).

```
cd circuits/pool
nargo test
nargo compile
```

Tested with nargo 1.0.0-beta.11. The Poseidon2 implementation comes from the `poseidon` package pinned in `Nargo.toml`.

## What the circuit proves

Public inputs, in the same order as `OpaquePool.publicInputs()`:

1. `root`
2. `nullifier0`
3. `nullifier1`
4. `commitment0`
5. `commitment1`
6. `asset_id`
7. `exit_amount`
8. `ext_data_hash`

For a spend of up to two notes of one asset:

- Each non-dummy input note is in the tree at `root`.
- Nullifiers are derived correctly and differ from each other.
- Every input and output note carries `asset_id` (it sits inside the commitment, `cm = H(1, stub, asset_id, amount)`).
- `in0 + in1 == out0 + out1 + exit_amount`, per asset.
- All amounts fit in 120 bits.

A zero-amount input is a dummy. It is not checked against the tree but still produces a nullifier.

## Not done yet

1. **Wallet-key binding.** Ownership is `opk = H(3, nk)` for now. v0 bound spends to a wallet key with an EIP-712 secp256k1 signature, about 73k of its 83k gates. That check still has to be ported.
2. **Matching on-chain hash.** `IHasher` in the contracts must be generated from the same Poseidon2 constants. Tests use a keccak stand-in.
3. **Verifier.** Generate the Solidity verifier with Barretenberg and wrap it in an `IVerifier` adapter.
4. **Lineage hooks.** Undecided, see `docs/DESIGN.md`. Must be settled before the circuit is frozen.
