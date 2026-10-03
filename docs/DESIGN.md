# Opaque design (draft)

Status: draft. Nothing here is final until the circuit is frozen.

## 1. Goals

- A shielded pool where holders of the flagship token ($OPA) who stay private earn a share of protocol fees.
- Immutable, no-admin core. The guardian can only pause new deposits.
- Open exit targets so private value can reach swaps, payments and other vaults without a trusted relayer.

## 2. Note format

Derived from v0, with the asset id moved inside the commitment.

```
stub = H(opk, rho, r)
cm   = H(1, stub, assetId, amount)
nf   = H(2, nk, cm, i)          // positional nullifier (faerie gold defense)
```

- Hash is Poseidon2 over BN254. Merkle tree depth 24, 64-root history.
- One shared tree for all assets. A larger anonymity set for every asset.
- A transaction spends and creates notes of one asset. The circuit enforces per-asset conservation.

## 3. Assets

| Asset | Note unit | Accrues donations |
| --- | --- | --- |
| ETH | wei, 1:1 | no |
| $OPA (flagship) | vault shares | yes |

- USDG and other issuer-controlled assets are out. An issuer freeze could poison the pool.
- ETH notes pay a fee that flows to flagship private holders.
- The share price of the flagship rises as donations arrive. Shares use virtual shares (V = 1e6) and a locked seed note, as in v0.

## 4. Fee flows (target)

- Holder share of fees well above 50%, final number set before launch and then fixed.
- Non-volume revenue: shield and unshield fees, and the ETH-note fee.
- The unshield fee is flat. An age-based fee would leak note age.
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

## 9. Open questions

1. Circuit freeze: include lineage hooks now, or ship v1 without them.
2. Asset id width and how new assets are registered without an admin.
3. Gas per private exit. v0 measured 4.7M to 5.2M, which may exceed public bundler limits.
4. Exact holder share and fee levels.
5. Native ETH handling in `IExitTarget` (send value vs approve).
