// Opaque pool transaction circuit (draft).
//
// Spends up to two notes of ONE asset, creates two notes, and optionally exits part of the value.
//
// Public inputs, in the order OpaquePool.publicInputs() builds them:
//   root, nullifier0, nullifier1, commitment0, commitment1, asset_id, exit_amount, ext_data_hash
//
// Note model (see docs/DESIGN.md):
//   stub = H(opk, rho, r)
//   cm   = H(1, stub, asset_id, amount)
//   nf   = H(2, nk, cm, index)
//   opk  = H(3, nk)
//
// DRAFT LIMITS. Not production:
//   - Ownership is `opk = H(3, nk)`. v0 bound spends to a wallet key through an EIP-712 secp256k1 signature
//     (about 73k of its 83k gates). That check is not ported yet, see docs/DESIGN.md.
//   - Poseidon2 here is Noir's standard-library instance. The on-chain IHasher must be generated to match it.
//   - Lineage hooks for clean-origin proofs are undecided and are NOT in this circuit.
use poseidon::poseidon2::Poseidon2;

global DEPTH: u32 = 24;
// keccak256("opaque") mod BN254 scalar field. Must equal MerkleTree.ZERO_LEAF.
global ZERO_LEAF: Field = 0x2fb59b7d0f99d0ee722695bf3dce13da949159db158e2304c1432d226b2fe50c;

pub struct InNote {
    nk: Field,
    rho: Field,
    r: Field,
    amount: Field,
    index: Field,
    path: [Field; DEPTH],
}

pub struct OutNote {
    opk: Field,
    rho: Field,
    r: Field,
    amount: Field,
}

pub fn hash2(a: Field, b: Field) -> Field {
    Poseidon2::hash([a, b], 2)
}

pub fn hash3(a: Field, b: Field, c: Field) -> Field {
    Poseidon2::hash([a, b, c], 3)
}

pub fn hash4(a: Field, b: Field, c: Field, d: Field) -> Field {
    Poseidon2::hash([a, b, c, d], 4)
}

pub fn owner_key(nk: Field) -> Field {
    hash2(3, nk)
}

pub fn commitment(opk: Field, rho: Field, r: Field, asset_id: Field, amount: Field) -> Field {
    hash4(1, hash3(opk, rho, r), asset_id, amount)
}

pub fn nullifier(nk: Field, cm: Field, index: Field) -> Field {
    hash4(2, nk, cm, index)
}

pub fn merkle_root(leaf: Field, index: Field, path: [Field; DEPTH]) -> Field {
    let bits: [u1; DEPTH] = index.to_le_bits();
    let mut node = leaf;
    for i in 0..DEPTH {
        node = if bits[i] == 0 {
            hash2(node, path[i])
        } else {
            hash2(path[i], node)
        };
    }
    node
}

/// Checks one input note and returns (its amount, its nullifier). A zero-amount input is a dummy and is
/// not required to be in the tree, but still gets a nullifier so both slots look the same on-chain.
fn check_input(note: InNote, asset_id: Field, root: Field) -> (Field, Field) {
    note.amount.assert_max_bit_size::<120>();
    let opk = owner_key(note.nk);
    let cm = commitment(opk, note.rho, note.r, asset_id, note.amount);
    if note.amount != 0 {
        assert(merkle_root(cm, note.index, note.path) == root, "input note not in tree");
    }
    (note.amount, nullifier(note.nk, cm, note.index))
}

fn check_output(note: OutNote, asset_id: Field) -> (Field, Field) {
    note.amount.assert_max_bit_size::<120>();
    (note.amount, commitment(note.opk, note.rho, note.r, asset_id, note.amount))
}

fn main(
    // public
    root: pub Field,
    nullifier0: pub Field,
    nullifier1: pub Field,
    commitment0: pub Field,
    commitment1: pub Field,
    asset_id: pub Field,
    exit_amount: pub Field,
    ext_data_hash: pub Field,
    // private
    in0: InNote,
    in1: InNote,
    out0: OutNote,
    out1: OutNote,
) {
    exit_amount.assert_max_bit_size::<120>();

    let (a0, n0) = check_input(in0, asset_id, root);
    let (a1, n1) = check_input(in1, asset_id, root);
    assert(n0 == nullifier0, "nullifier0 mismatch");
    assert(n1 == nullifier1, "nullifier1 mismatch");
    assert(n0 != n1, "duplicate nullifier");

    let (b0, c0) = check_output(out0, asset_id);
    let (b1, c1) = check_output(out1, asset_id);
    assert(c0 == commitment0, "commitment0 mismatch");
    assert(c1 == commitment1, "commitment1 mismatch");

    // per-asset conservation: every note above was committed under the same asset_id
    assert(a0 + a1 == b0 + b1 + exit_amount, "value not conserved");

    // ext_data_hash has no constraint of its own. Being a public input binds the proof to it.
    let _ = ext_data_hash;
}

// ------------------------------------------------------------------ tests

fn zero_hashes() -> [Field; DEPTH] {
    let mut z = [0; DEPTH];
    let mut cur = ZERO_LEAF;
    for i in 0..DEPTH {
        z[i] = cur;
        cur = hash2(cur, cur);
    }
    z
}

fn dummy_in(nk: Field) -> InNote {
    InNote { nk, rho: 77, r: 88, amount: 0, index: 0, path: [0; DEPTH] }
}

#[test]
fn spend_and_exit() {
    let asset: Field = 1;
    let nk: Field = 1234;
    let opk = owner_key(nk);

    // a tree holding one note at index 0
    let cm = commitment(opk, 11, 22, asset, 100);
    let zs = zero_hashes();
    let root = merkle_root(cm, 0, zs);

    let in0 = InNote { nk, rho: 11, r: 22, amount: 100, index: 0, path: zs };
    let in1 = dummy_in(nk);
    let out0 = OutNote { opk, rho: 33, r: 44, amount: 60 };
    let out1 = OutNote { opk, rho: 55, r: 66, amount: 0 };

    let n0 = nullifier(nk, cm, 0);
    let n1 = nullifier(nk, commitment(opk, 77, 88, asset, 0), 0);
    let c0 = commitment(opk, 33, 44, asset, 60);
    let c1 = commitment(opk, 55, 66, asset, 0);

    main(root, n0, n1, c0, c1, asset, 40, 999, in0, in1, out0, out1);
}

#[test(should_fail_with = "value not conserved")]
fn cannot_mint() {
    let asset: Field = 1;
    let nk: Field = 1234;
    let opk = owner_key(nk);
    let cm = commitment(opk, 11, 22, asset, 100);
    let zs = zero_hashes();
    let root = merkle_root(cm, 0, zs);
    let in0 = InNote { nk, rho: 11, r: 22, amount: 100, index: 0, path: zs };
    let in1 = dummy_in(nk);
    let out0 = OutNote { opk, rho: 33, r: 44, amount: 101 };
    let out1 = OutNote { opk, rho: 55, r: 66, amount: 0 };
    let n0 = nullifier(nk, cm, 0);
    let n1 = nullifier(nk, commitment(opk, 77, 88, asset, 0), 0);
    main(
        root,
        n0,
        n1,
        commitment(opk, 33, 44, asset, 101),
        commitment(opk, 55, 66, asset, 0),
        asset,
        0,
        0,
        in0,
        in1,
        out0,
        out1,
    );
}

#[test(should_fail_with = "input note not in tree")]
fn cannot_spend_unknown_note() {
    let asset: Field = 1;
    let nk: Field = 1234;
    let opk = owner_key(nk);
    let zs = zero_hashes();
    let root = merkle_root(commitment(opk, 11, 22, asset, 100), 0, zs);
    // claims 500 under the same randomness, so the commitment is not in the tree
    let in0 = InNote { nk, rho: 11, r: 22, amount: 500, index: 0, path: zs };
    let in1 = dummy_in(nk);
    let out0 = OutNote { opk, rho: 33, r: 44, amount: 500 };
    let out1 = OutNote { opk, rho: 55, r: 66, amount: 0 };
    let bad_cm = commitment(opk, 11, 22, asset, 500);
    main(
        root,
        nullifier(nk, bad_cm, 0),
        nullifier(nk, commitment(opk, 77, 88, asset, 0), 0),
        commitment(opk, 33, 44, asset, 500),
        commitment(opk, 55, 66, asset, 0),
        asset,
        0,
        0,
        in0,
        in1,
        out0,
        out1,
    );
}

#[test(should_fail_with = "value not conserved")]
fn cannot_exit_more_than_spent() {
    let asset: Field = 2;
    let nk: Field = 5;
    let opk = owner_key(nk);
    let cm = commitment(opk, 1, 2, asset, 10);
    let zs = zero_hashes();
    let root = merkle_root(cm, 0, zs);
    let in0 = InNote { nk, rho: 1, r: 2, amount: 10, index: 0, path: zs };
    let in1 = dummy_in(nk);
    let out0 = OutNote { opk, rho: 3, r: 4, amount: 0 };
    let out1 = OutNote { opk, rho: 5, r: 6, amount: 0 };
    main(
        root,
        nullifier(nk, cm, 0),
        nullifier(nk, commitment(opk, 77, 88, asset, 0), 0),
        commitment(opk, 3, 4, asset, 0),
        commitment(opk, 5, 6, asset, 0),
        asset,
        11,
        0,
        in0,
        in1,
        out0,
        out1,
    );
}

#[test(should_fail_with = "input note not in tree")]
fn note_cannot_be_spent_under_another_asset() {
    // The note was created under asset 1. Spending it as asset 2 changes its commitment, so it is not in the tree.
    let nk: Field = 5;
    let opk = owner_key(nk);
    let cm = commitment(opk, 1, 2, 1, 10);
    let zs = zero_hashes();
    let root = merkle_root(cm, 0, zs);
    let in0 = InNote { nk, rho: 1, r: 2, amount: 10, index: 0, path: zs };
    let in1 = dummy_in(nk);
    let out0 = OutNote { opk, rho: 3, r: 4, amount: 10 };
    let out1 = OutNote { opk, rho: 5, r: 6, amount: 0 };
    let wrong_cm = commitment(opk, 1, 2, 2, 10);
    main(
        root,
        nullifier(nk, wrong_cm, 0),
        nullifier(nk, commitment(opk, 77, 88, 2, 0), 0),
        commitment(opk, 3, 4, 2, 10),
        commitment(opk, 5, 6, 2, 0),
        2,
        0,
        0,
        in0,
        in1,
        out0,
        out1,
    );
}
