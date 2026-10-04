# Opaque design (draft)

Status: draft. Nothing here is final until the circuit is frozen.

## 1. Goals

- A shielded pool where holders of the flagship token ($OPA) who stay private earn a share of protocol fees.
- Immutable, no-admin core. The guardian can only pause new deposits.
- Open exit targets so private value can reach swaps, payments and other vaults without a trusted relayer.

## 2. Note format

Derived from v0, with the asset id moved inside the commitment. The pool is $OPA-only (asset id 1). The field stays in the note so a later pool version can add assets without a new circuit.

```
stub = H(opk, rho, r)
cm   = H(1, stub, assetId, amount)
nf   = H(2, nk, cm, i)          // positional nullifier (faerie gold defense)
```

- Hash is Poseidon2 over BN254. Merkle tree depth 24, 64-root history.
- One tree. The anonymity set is the $OPA holders who shield, which is smaller than a multi-asset pool would give. This is a deliberate tradeoff for a smaller audit surface and a simpler pitch.
- A transaction spends and creates notes of one asset. The circuit enforces per-asset conservation, which is trivially one asset today.

## 3. Assets

| Asset | Note unit | Accrues donations |
| --- | --- | --- |
| $OPA (id 1) | vault shares | yes |

- ETH, USDG and every other token are out. ETH sent to the pool is rejected. Issuer-controlled assets are out on purpose: an issuer freeze could poison the pool.
- Decision (changed from the earlier draft): the first design had ETH as a second asset to widen the anonymity set and earn fee revenue. It was removed. ETH could be added in a later pool version.
- The share price rises as donations arrive. Shares use virtual shares (V = 1e6) and a locked seed note, as in v0.

## 4. Fee flows (target)

- Holder share of fees well above 50%, final number set before launch and then fixed.
- Revenue that does not depend on trading volume: an unshield fee in $OPA, a percentage of each exit. There is no shield fee. The unshield fee stays in the pool as backing, so it goes to everyone still shielded, and the pool pays nothing to any address.
- The unshield fee depends only on the amount being exited, which is public anyway. An age-based fee would leak note age.
- The pool has no fee sink. Pons trade fees reach the pool only through the harvester (`docs/HARVESTER.md`), which buys $OPA and donates it.
- Public holders get no yield. They get price support from buybacks and the shrinking float.

## 5. Exits

The vault acts as an ERC-4337 account. `validateUserOp` performs the full state transition. `execute4337` settles the exit to an `IExitTarget`.

- Target is named in the proof, so the relayer cannot redirect it.
- A target manifest is shown to the user before signing.
- An events-only registry plus a UI "verified" badge lists known targets. The registry has no power over the vault.

## 6. Disclosure keys

- Single-payment receipt: proves one note to one party.
- Full view key ("audit key"): read-only view of an account.
- Period report bundle: a signed export for a date range.
- Teams: MPC or EIP-7702 owners. Contract multisigs cannot own notes.

## 7. Clean-origin proofs (research)

Association sets let a user prove their funds are not from a flagged set without revealing which note is theirs.

Hard problem: lineage through note merge and split. Preferred design is an exit-time lineage proof. Parked for v1, but it decides whether the circuit is frozen with hooks for it. This is the main open question for the freeze.

## 8. In-pool swaps (research)

Real in-pool swaps need an in-circuit epoch swap in the style of Penumbra ZSwap. Until then, cross-asset moves are exit then shield through a target.

## 9. Implementation status

- `contracts/src/OpaquePool.sol`: shield, transact, donate, fee collection, caps, guardian pause. Tested with a mock hasher and verifier.
- `contracts/src/Poseidon2Hasher.sol`: generated Poseidon2 (BN254, t = 4). Matches the circuit on every reference vector, and the pool's tree roots match the circuit's Merkle function.
- `circuits/pool/scripts/build_verifier.sh`: proof and verifier pipeline. Not run end to end yet (the trusted-setup download was blocked where it was written).
- `circuits/pool`: asset-aware spend circuit. Compiles and passes its tests. No wallet-key binding yet.
- Exits are plain transfers to the recipient. Exit targets (`IExitTarget`) are not wired in. A transaction with non-empty `ext.data` reverts for now.
- The ERC-4337 account path from v0 is not ported.

## 10. Open questions

1. Circuit freeze: include lineage hooks now, or ship v1 without them.
2. If assets are ever added: asset id width and how they are registered without an admin (a new pool version is the likely path).
3. Gas per private exit. v0 measured 4.7M to 5.2M, which may exceed public bundler limits. With the generated Poseidon2 hasher, one tree insert costs about 24 hashes at roughly 41k gas each (about 1M), so a transaction that adds two notes is about 2M before proof verification. Worth optimizing (a cheaper hash call path, or inserting aligned pairs together) before launch.
4. Exact holder share and fee levels.
5. Exit-target payloads for $OPA only, plus whether ETH ever returns.
6. Note encryption format and the epoch scheme (see section 11).

## 11. Research: forward-secure, PQ-ready note encryption

Status: research. Nothing here changes the circuit.

### Problem

Each transaction carries two ciphertexts (`ct0`, `ct1` in `ExtData`) so recipients can find and read their notes. They stay on chain forever, which gives two long-term risks:

- **Key leak.** If a recipient's viewing or decryption key leaks, every past note encrypted to it can be read.
- **Harvest now, decrypt later.** If the key exchange is elliptic-curve only, someone can store ciphertexts today and decrypt them once a large quantum computer exists.

The pool's commitments and nullifiers use Poseidon, which is hash-based. The proof system (UltraHonk over BN254) is not post-quantum. A quantum attacker's main power there is forging proofs, not reading old notes, so the ciphertext is the privacy gap that matters first.

### Proposal for v1 (no format change needed later)

1. **Hybrid key exchange.** Recipients publish an elliptic-curve receiving key and an ML-KEM-768 encapsulation key. The sender derives one AEAD key from both shared secrets with HKDF, bound to the transaction (pool address, chain id, output index, epoch). An attacker must break both to read a note.
2. **Versioned ciphertext.** `version (1) | epoch (4) | ec_ephemeral (33) | kem_ct (1088) | nonce (12) | aead_ct | tag (16)`. The epoch field is there from day one, even if v1 always sets it to 0, so epoch keys can be added without a format change.
3. **Plaintext.** `assetId | amount | rho | r` plus a short memo field. Padded to a fixed length so ciphertext sizes do not leak the content type.
4. **Calldata, not storage.** Ciphertexts go in event data only. Rough size is about 1.2 KB per ciphertext and about 2.4 KB per two-note transaction. At L1 calldata pricing (16 gas per nonzero byte) that is on the order of 40k gas. Real cost on Robinhood Chain must be measured.

### Epoch keys (later, optional)

Goal: leaking a key from today should not expose old notes, and a user should be able to disclose a date range without disclosing everything (this also serves the period report in section 6).

Options, with trade-offs:

- **Cold master key, per-epoch hot keys (elliptic-curve part).** Derive `sk_e = sk_master + H(pk_master, e)`. The master stays offline, the device holds only recent epoch keys, and range disclosure is just handing over the keys for those epochs. This limits damage but is not strict forward secrecy: if the master leaks, everything leaks.
- **Pre-published key bundles (needed for the ML-KEM part).** ML-KEM has no additive key derivation, so per-epoch ML-KEM keys must be generated in advance and published. Costs: someone has to host the bundles, and looking them up reveals who is receiving.
- **Tree-based forward-secure encryption.** Strict forward secrecy through key evolution. Lattice-based versions exist but are large and slow. Out of scope until a concrete need appears.

Open: how a payer learns the receiver's current epoch key without a lookup that leaks activity (registry, rotating stealth meta-address, or out-of-band).

### Epoch-bounded notes (not recommended for now)

An alternative idea is to expire nullifiers after N epochs and force notes to be migrated. It bounds nullifier-set growth, but it makes users do periodic work and the migration timing leaks metadata. Decaying linkability (nullifiers that stop being linkable) is not safe: it allows double spends.

### Moving to a post-quantum proof system

The pool is immutable, so a future proof system means a new pool version. Design for this now:

- A versioned pool. The next version's circuit accepts nullifiers from the old pool, so users can migrate inside the proof without a public unshield and reshield.
- Candidate: a hash-based proof system (STARK style). Verification cost on the EVM has to be checked before committing.
- Do not use "post-quantum" as a marketing claim until the commitments, the proofs and the encryption all are.

### Rejected ideas

- **Replacing the Merkle-Poseidon pool with lattice ring signatures.** Smaller anonymity sets than a full-pool SNARK, signatures of tens to hundreds of KB, no EVM precompiles, and it discards the circuit and tests built so far.
- **Dynamic security tiers chosen by a threat oracle.** Needs an admin, which contradicts the no-admin core, and visible tiers split the anonymity set.
- **FHE on shielded balances.** Not practical on the EVM and someone still has to compute and decrypt.
- **Notary-set bridges.** Reintroduce a trusted set. A ZK light-client proof is the better primitive.
