// Builds the circuit inputs (a Prover.toml) for one pool transaction: spend one or two notes, create two notes,
// optionally exit part of the value. It checks everything the circuit checks first, so a mistake shows up here
// with a readable message instead of as a failed proof.
import { FIELD } from "./poseidon2.ts";
import { MAX_AMOUNT, type Note, commitment, nullifier, ownerKey } from "./notes.ts";
import { DEPTH, MerkleTree } from "./tree.ts";

export type SpendInput = {
  nk: bigint;
  note: Note;
  /** Leaf index of the note in the pool's tree. */
  index: number;
};

export type OutputNote = Note;

export type TransactionSpec = {
  tree: MerkleTree;
  assetId: bigint;
  inputs: SpendInput[]; // one or two
  outputs: [OutputNote, OutputNote];
  exitAmount: bigint;
  extDataHash: bigint;
  /** Randomness for the dummy second input when only one note is spent. Defaults to fresh random values. */
  dummy?: { rho: bigint; r: bigint };
};

export type PublicInputs = {
  root: bigint;
  nullifier0: bigint;
  nullifier1: bigint;
  commitment0: bigint;
  commitment1: bigint;
  assetId: bigint;
  exitAmount: bigint;
  extDataHash: bigint;
};

/** The same inputs as `proverToml`, shaped for noir_js: every field element is a 0x hex string. */
export type CircuitInputs = Record<string, unknown>;

export type Witness = { publicInputs: PublicInputs; proverToml: string; circuitInputs: CircuitInputs };

const hex = (v: bigint): string => '"0x' + v.toString(16).padStart(64, "0") + '"';

function randomField(): bigint {
  const b = new Uint8Array(32);
  globalThis.crypto.getRandomValues(b);
  let v = 0n;
  for (const x of b) v = (v << 8n) | BigInt(x);
  return v % FIELD;
}

export function buildWitness(spec: TransactionSpec): Witness {
  const { tree, assetId, outputs, exitAmount } = spec;
  if (spec.inputs.length < 1 || spec.inputs.length > 2) throw new Error("spend one or two notes");
  if (exitAmount < 0n || exitAmount > MAX_AMOUNT) throw new Error("exit amount out of range");
  if (spec.extDataHash < 0n || spec.extDataHash >= FIELD) throw new Error("ext data hash is not a field element");

  const nk = spec.inputs[0].nk;
  type Slot = { nk: bigint; note: Note; index: number; path: bigint[]; cm: bigint; nf: bigint };
  const slots: Slot[] = spec.inputs.map((inp, k) => {
    if (inp.note.assetId !== assetId) throw new Error(`input ${k} is a note of another asset`);
    if (ownerKey(inp.nk) !== inp.note.opk) throw new Error(`input ${k} is not owned by this nullifier key`);
    const cm = commitment(inp.note);
    const path = tree.path(inp.index);
    if (MerkleTree.rootFromPath(cm, inp.index, path) !== tree.root) {
      throw new Error(`input ${k} is not in the tree (wrong index, amount or randomness)`);
    }
    return { nk: inp.nk, note: inp.note, index: inp.index, path, cm, nf: nullifier(inp.nk, cm, BigInt(inp.index)) };
  });

  if (slots.length === 1) {
    // a zero-amount dummy: not checked against the tree, but still gets a nullifier so both slots look alike
    const d = spec.dummy ?? { rho: randomField(), r: randomField() };
    const note: Note = { opk: ownerKey(nk), rho: d.rho, r: d.r, assetId, amount: 0n };
    const cm = commitment(note);
    slots.push({ nk, note, index: 0, path: new Array(DEPTH).fill(0n), cm, nf: nullifier(nk, cm, 0n) });
  }
  if (slots[0].nf === slots[1].nf) throw new Error("the two inputs have the same nullifier");

  for (const [k, o] of outputs.entries()) {
    if (o.assetId !== assetId) throw new Error(`output ${k} is a note of another asset`);
  }
  const inSum = slots[0].note.amount + slots[1].note.amount;
  const outSum = outputs[0].amount + outputs[1].amount + exitAmount;
  if (inSum !== outSum) throw new Error(`value not conserved: in ${inSum}, out ${outSum}`);

  const c0 = commitment(outputs[0]);
  const c1 = commitment(outputs[1]);

  const publicInputs: PublicInputs = {
    root: tree.root,
    nullifier0: slots[0].nf,
    nullifier1: slots[1].nf,
    commitment0: c0,
    commitment1: c1,
    assetId,
    exitAmount,
    extDataHash: spec.extDataHash,
  };

  const lines: string[] = [];
  lines.push(`root = ${hex(publicInputs.root)}`);
  lines.push(`nullifier0 = ${hex(publicInputs.nullifier0)}`);
  lines.push(`nullifier1 = ${hex(publicInputs.nullifier1)}`);
  lines.push(`commitment0 = ${hex(publicInputs.commitment0)}`);
  lines.push(`commitment1 = ${hex(publicInputs.commitment1)}`);
  lines.push(`asset_id = ${hex(publicInputs.assetId)}`);
  lines.push(`exit_amount = ${hex(publicInputs.exitAmount)}`);
  lines.push(`ext_data_hash = ${hex(publicInputs.extDataHash)}`);
  slots.forEach((s, k) => {
    lines.push("", `[in${k}]`);
    lines.push(`nk = ${hex(s.nk)}`);
    lines.push(`rho = ${hex(s.note.rho)}`);
    lines.push(`r = ${hex(s.note.r)}`);
    lines.push(`amount = ${hex(s.note.amount)}`);
    lines.push(`index = ${hex(BigInt(s.index))}`);
    lines.push(`path = [${s.path.map(hex).join(", ")}]`);
  });
  outputs.forEach((o, k) => {
    lines.push("", `[out${k}]`);
    lines.push(`opk = ${hex(o.opk)}`);
    lines.push(`rho = ${hex(o.rho)}`);
    lines.push(`r = ${hex(o.r)}`);
    lines.push(`amount = ${hex(o.amount)}`);
  });
  const h = (v: bigint) => "0x" + v.toString(16).padStart(64, "0");
  const circuitInputs: CircuitInputs = {
    root: h(publicInputs.root),
    nullifier0: h(publicInputs.nullifier0),
    nullifier1: h(publicInputs.nullifier1),
    commitment0: h(publicInputs.commitment0),
    commitment1: h(publicInputs.commitment1),
    asset_id: h(publicInputs.assetId),
    exit_amount: h(publicInputs.exitAmount),
    ext_data_hash: h(publicInputs.extDataHash),
  };
  slots.forEach((s, k) => {
    circuitInputs[`in${k}`] = {
      nk: h(s.nk),
      rho: h(s.note.rho),
      r: h(s.note.r),
      amount: h(s.note.amount),
      index: h(BigInt(s.index)),
      path: s.path.map(h),
    };
  });
  outputs.forEach((o, k) => {
    circuitInputs[`out${k}`] = { opk: h(o.opk), rho: h(o.rho), r: h(o.r), amount: h(o.amount) };
  });
  return { publicInputs, proverToml: lines.join("\n") + "\n", circuitInputs };
}
