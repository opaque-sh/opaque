// Note model, the same as circuits/pool/src/main.nr and docs/DESIGN.md:
//   opk  = H(3, nk)
//   stub = H(opk, rho, r)
//   cm   = H(1, stub, assetId, amount)
//   nf   = H(2, nk, cm, index)
// `nk` is the owner's secret nullifier key. `rho` and `r` are fresh randomness per note.
import { FIELD, hash2, hash3, hash4 } from "./poseidon2.ts";
import { fromHex, keccak256, toHex } from "./keccak.ts";

export type Note = { opk: bigint; rho: bigint; r: bigint; assetId: bigint; amount: bigint };

/** Notes carry 120-bit amounts, as the contract and the circuit require. */
export const MAX_AMOUNT = (1n << 120n) - 1n;

export const ownerKey = (nk: bigint): bigint => hash2(3n, nk);

export const noteStub = (opk: bigint, rho: bigint, r: bigint): bigint => hash3(opk, rho, r);

export function commitment(n: Note): bigint {
  if (n.amount < 0n || n.amount > MAX_AMOUNT) throw new Error("amount does not fit in 120 bits");
  return hash4(1n, noteStub(n.opk, n.rho, n.r), n.assetId, n.amount);
}

export const nullifier = (nk: bigint, cm: bigint, index: bigint): bigint => hash4(2n, nk, cm, index);

/** What a wallet sends to `OpaquePool.shroud(stub, amount, ciphertext)`: the stub, not the whole commitment. */
export const shroudStub = (opk: bigint, rho: bigint, r: bigint): bigint => noteStub(opk, rho, r);

// ---------------------------------------------------------------- ext data

export type ExtData = {
  recipient: string; // 0x address
  caller: string; // 0x address, zero address means anyone may submit
  fee: bigint; // relayer fee in shares
  data: Uint8Array; // must be empty for now
  ciphertext0: Uint8Array;
  ciphertext1: Uint8Array;
};

const word = (v: bigint): Uint8Array => {
  const out = new Uint8Array(32);
  let x = v;
  for (let i = 31; i >= 0; i--) {
    out[i] = Number(x & 0xffn);
    x >>= 8n;
  }
  return out;
};

const addr = (a: string): bigint => {
  if (!/^0x[0-9a-fA-F]{40}$/.test(a)) throw new Error("bad address: " + a);
  return BigInt(a);
};

/**
 * Same as `OpaquePool.extDataHash`:
 * keccak256(abi.encode(recipient, caller, fee, keccak256(data), keccak256(ciphertext0), keccak256(ciphertext1))) mod field.
 */
export function extDataHash(e: ExtData): bigint {
  const parts = [
    word(addr(e.recipient)),
    word(addr(e.caller)),
    word(e.fee),
    keccak256(e.data),
    keccak256(e.ciphertext0),
    keccak256(e.ciphertext1),
  ];
  const buf = new Uint8Array(32 * parts.length);
  parts.forEach((p, i) => buf.set(p, i * 32));
  return BigInt(toHex(keccak256(buf))) % FIELD;
}

export const hexToBytes = fromHex;
