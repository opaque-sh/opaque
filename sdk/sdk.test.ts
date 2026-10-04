import test from "node:test";
import assert from "node:assert/strict";
import { hash2, hash4 } from "./poseidon2.ts";
import { type Note, commitment, extDataHash, nullifier, ownerKey } from "./notes.ts";
import { EMPTY_ROOT, MerkleTree, ZERO_LEAF } from "./tree.ts";
import { buildWitness } from "./witness.ts";

// Values below come from the circuit's example proof (circuits/pool/Prover.toml), made by `bb`, and from the
// Solidity tests (Poseidon2.t.sol). The TypeScript must reproduce them exactly.
const EXAMPLE = {
  nk: 1234n,
  opk: 0x19e1a720c09e1914ada90f60972492c8d8fd86eccd0aaa9ed22ee503e1cb416an,
  root: 0x0b80e54b05c6da4dd39949702e9f498889aebd232770065ed51c02a3cbc0ac3an,
  nullifier0: 0x1886442a7d8c7334acf05ef1d0ae98f4aba251f13c730adc8bc94d34719b3217n,
  nullifier1: 0x12307d79698dcbd681dca6129127e78ac5a34ae9bf0bc82ffff0aed7680de09dn,
  commitment0: 0x155597d42e6ea1588437aef66696fb06096bd977a1dfb3964a91446a5f138193n,
  commitment1: 0x07294c6fdf836114369fda8befc32d972a789d314cfa9343874ad348b331dd10n,
};

test("owner key matches the circuit", () => {
  assert.equal(ownerKey(EXAMPLE.nk), EXAMPLE.opk);
});

test("empty tree root matches the contract", () => {
  assert.equal(EMPTY_ROOT, 0x0ae5127e85ed8bc5bb8b69fdc41b3a35e0eea45834ac2b2b433975cc014ebb92n);
  const t = new MerkleTree();
  assert.equal(t.root, EMPTY_ROOT);
  assert.equal(ZERO_LEAF, 0x2fb59b7d0f99d0ee722695bf3dce13da949159db158e2304c1432d226b2fe50cn);
});

test("example root, nullifiers and commitments match the proof's public inputs", () => {
  const note: Note = { opk: EXAMPLE.opk, rho: 11n, r: 22n, assetId: 1n, amount: 100n };
  const tree = new MerkleTree();
  tree.insert(commitment(note));
  assert.equal(tree.root, EXAMPLE.root);

  const w = buildWitness({
    tree,
    assetId: 1n,
    inputs: [{ nk: EXAMPLE.nk, note, index: 0 }],
    outputs: [
      { opk: EXAMPLE.opk, rho: 33n, r: 44n, assetId: 1n, amount: 60n },
      { opk: EXAMPLE.opk, rho: 55n, r: 66n, assetId: 1n, amount: 0n },
    ],
    exitAmount: 40n,
    extDataHash: 999n,
    dummy: { rho: 77n, r: 88n },
  });
  assert.equal(w.publicInputs.root, EXAMPLE.root);
  assert.equal(w.publicInputs.nullifier0, EXAMPLE.nullifier0);
  assert.equal(w.publicInputs.nullifier1, EXAMPLE.nullifier1);
  assert.equal(w.publicInputs.commitment0, EXAMPLE.commitment0);
  assert.equal(w.publicInputs.commitment1, EXAMPLE.commitment1);
});

test("one-leaf root matches the contract", () => {
  // Poseidon2.t.sol: shrouding 999_000_000_000 tokens into an empty pool mints 0.999e18 shares, so the leaf is
  // hash4(1, stub = 12345, asset 1, 0.999e18), and the contract's root is the value below.
  const t = new MerkleTree();
  t.insert(hash4(1n, 12345n, 1n, 999_000_000_000_000_000n));
  assert.equal(t.root, 0x28f0c18ed00c5247f6d5cd0fd3bcc1ce8d4984239fa55e9c4637b0955bf29c18n);
});

test("tree: paths recompute the root for every leaf", () => {
  const t = new MerkleTree();
  for (let i = 0; i < 11; i++) t.insert(hash2(BigInt(i), 5n));
  for (let i = 0; i < 11; i++) {
    const leaf = hash2(BigInt(i), 5n);
    assert.equal(MerkleTree.rootFromPath(leaf, i, t.path(i)), t.root);
  }
});

test("witness rejects what the circuit would reject", () => {
  const note: Note = { opk: ownerKey(5n), rho: 1n, r: 2n, assetId: 1n, amount: 10n };
  const tree = new MerkleTree();
  tree.insert(commitment(note));
  const out = (amount: bigint): Note => ({ opk: ownerKey(5n), rho: 3n, r: 4n, assetId: 1n, amount });
  const base = {
    tree,
    assetId: 1n,
    inputs: [{ nk: 5n, note, index: 0 }],
    outputs: [out(5n), out(0n)] as [Note, Note],
    exitAmount: 5n,
    extDataHash: 0n,
  };
  buildWitness(base);
  assert.throws(() => buildWitness({ ...base, exitAmount: 6n }), /value not conserved/);
  assert.throws(() => buildWitness({ ...base, inputs: [{ nk: 6n, note, index: 0 }] }), /not owned/);
  assert.throws(
    () => buildWitness({ ...base, inputs: [{ nk: 5n, note: { ...note, amount: 11n }, index: 0 }] }),
    /not in the tree/,
  );
  assert.throws(() => buildWitness({ ...base, assetId: 2n }), /another asset/);
});

test("the Prover.toml text has every field the circuit reads", () => {
  const note: Note = { opk: ownerKey(5n), rho: 1n, r: 2n, assetId: 1n, amount: 10n };
  const tree = new MerkleTree();
  tree.insert(commitment(note));
  const w = buildWitness({
    tree,
    assetId: 1n,
    inputs: [{ nk: 5n, note, index: 0 }],
    outputs: [
      { opk: ownerKey(5n), rho: 3n, r: 4n, assetId: 1n, amount: 10n },
      { opk: ownerKey(5n), rho: 5n, r: 6n, assetId: 1n, amount: 0n },
    ],
    exitAmount: 0n,
    extDataHash: 7n,
  });
  for (const key of ["root", "nullifier0", "nullifier1", "commitment0", "commitment1", "asset_id", "exit_amount", "ext_data_hash", "[in0]", "[in1]", "[out0]", "[out1]"]) {
    assert.ok(w.proverToml.includes(key), key);
  }
  assert.equal((w.proverToml.match(/path = \[/g) ?? []).length, 2);
});

test("nullifier is bound to the index", () => {
  assert.notEqual(nullifier(1n, 2n, 0n), nullifier(1n, 2n, 1n));
  assert.equal(hash4(2n, 1n, 2n, 0n), nullifier(1n, 2n, 0n));
});

test("ext data hash has the right shape", () => {
  const h = extDataHash({
    recipient: "0x00000000000000000000000000000000000b0b00",
    caller: "0x0000000000000000000000000000000000000000",
    fee: 0n,
    data: new Uint8Array(),
    ciphertext0: new Uint8Array(),
    ciphertext1: new Uint8Array(),
  });
  assert.ok(h > 0n && h < 21888242871839275222246405745257275088548364400416034343698204186575808495617n);
});

test("ext data hash matches the value computed with Foundry (abi.encode, keccak, mod field)", () => {
  // from `cast abi-encode "f(address,address,uint256,bytes32,bytes32,bytes32)"` and `cast keccak`, reduced mod the field
  const h = extDataHash({
    recipient: "0x00000000000000000000000000000000000b0b00",
    caller: "0x00000000000000000000000000000000000c0c00",
    fee: 12345n,
    data: new Uint8Array(),
    ciphertext0: new Uint8Array([0xca, 0xfe]),
    ciphertext1: new Uint8Array([0xbe, 0xef, 0x01]),
  });
  assert.equal(h, 0x15de789b1fb5b4dec82bb01269290e1617a5d718105c650e659a2e1548e34c3n);
});
