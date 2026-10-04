# SDK (draft)

TypeScript, no dependencies. Needs Node 22 (it runs `.ts` files directly).

```
cd sdk
npm test            # hash, tree, notes, witness builder, entropy
npm run e2e:gen     # rewrite circuits/pool/e2e.toml and contracts/test/fixtures/e2e_scenario.json
```

| File | What it does |
| --- | --- |
| `poseidon2.ts` | Poseidon2 over BN254, the same hash as the circuit and `Poseidon2Hasher.sol`. Constants are generated from the Solidity by `tools/gen_poseidon2_ts.py` |
| `keccak.ts` | Keccak-256 (Ethereum's), used for the ext data hash |
| `notes.ts` | Owner key, note commitment, nullifier, and `extDataHash`, matching `OpaquePool.extDataHash` |
| `tree.ts` | The depth-24 Merkle tree with the pool's empty leaf, with paths for the circuit |
| `witness.ts` | Builds a `Prover.toml` for one transaction and checks everything the circuit checks first |
| `x25519.ts` | X25519 from RFC 7748, checked against its vectors. Not constant time, replace with an audited library before wallet use |
| `keys.ts` | Account keys from one wallet signature, and addresses (opk plus view public key) |
| `encrypt.ts` | Note encryption to a view key: X25519, HKDF-SHA256, AES-256-GCM, 173 bytes |
| `scan.ts` | Rebuilds the tree from `NoteAdded` events and finds your notes, checking each commitment |
| `entropy.ts` | Mixes pointer movement into note secrets, never weaker than the system random source |
| `e2e.ts` | The fixed end-to-end scenario: a shroud and a partial unshroud |

What is checked: the TypeScript reproduces the circuit's example public inputs (made by `bb`), the contract's empty
and one-leaf roots, and Foundry's ext data hash. The circuit solves a witness the SDK builds for the scenario, and
`OpaquePoolE2E.t.sol` shows the real pool's root equals the SDK's.

Not built yet: fetching events from a node, key and note storage, the browser prover, the relayer client. The key and
encryption decisions are in `docs/DESIGN.md`.
