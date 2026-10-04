// Poseidon2 over BN254 (t = 4), the same hash as Noir's `poseidon::poseidon2::Poseidon2::hash`, the Solidity
// `Poseidon2Hasher` and the circuit. Plain BigInt: slow compared with a native build, fine for a wallet that hashes
// a few dozen values per transaction.
//
// Sponge, rate 3, capacity 1: the state starts as [inputs..., 0 padding..., iv] with iv = n * 2^64 for n inputs.
// More than three inputs absorb into state[0..2] by field addition between permutations.
import { FULL_ROUND_CONSTANTS, INTERNAL_DIAGONAL, PARTIAL_ROUND_CONSTANTS } from "./poseidon2_constants.ts";

export const FIELD = 21888242871839275222246405745257275088548364400416034343698204186575808495617n;
const TWO_POW_64 = 1n << 64n;

const add = (a: bigint, b: bigint) => (a + b) % FIELD;
const mul = (a: bigint, b: bigint) => (a * b) % FIELD;
const sbox = (x: bigint) => {
  const x2 = mul(x, x);
  return mul(mul(x2, x2), x);
};

type State = [bigint, bigint, bigint, bigint];

// The external matrix, on a width-4 state.
function externalMatrix(s: State): State {
  const [x0, x1, x2, x3] = s;
  const t0 = add(x0, x1);
  const t1 = add(x2, x3);
  const t2 = add(add(x1, x1), t1);
  const t3 = add(add(x3, x3), t0);
  const t4 = add(add(add(t1, t1), add(t1, t1)), t3);
  const t5 = add(add(add(t0, t0), add(t0, t0)), t2);
  return [add(t3, t5), t5, add(t2, t4), t4];
}

function fullRound(s: State, k: bigint[]): State {
  return externalMatrix([sbox(add(s[0], k[0])), sbox(add(s[1], k[1])), sbox(add(s[2], k[2])), sbox(add(s[3], k[3]))]);
}

function partialRound(s: State, k: bigint): State {
  const x0 = sbox(add(s[0], k));
  const sum = add(add(x0, s[1]), add(s[2], s[3]));
  return [
    add(mul(x0, INTERNAL_DIAGONAL[0]), sum),
    add(mul(s[1], INTERNAL_DIAGONAL[1]), sum),
    add(mul(s[2], INTERNAL_DIAGONAL[2]), sum),
    add(mul(s[3], INTERNAL_DIAGONAL[3]), sum),
  ];
}

export function permute(input: State): State {
  let s = externalMatrix(input);
  for (let i = 0; i < 4; i++) s = fullRound(s, FULL_ROUND_CONSTANTS[i]);
  for (let i = 0; i < 56; i++) s = partialRound(s, PARTIAL_ROUND_CONSTANTS[i]);
  for (let i = 4; i < 8; i++) s = fullRound(s, FULL_ROUND_CONSTANTS[i]);
  return s;
}

function check(v: bigint): bigint {
  if (v < 0n || v >= FIELD) throw new Error("value is not a field element");
  return v;
}

export function hash(inputs: bigint[]): bigint {
  const n = inputs.length;
  if (n === 0) throw new Error("nothing to hash");
  inputs.forEach(check);
  let s: State = [0n, 0n, 0n, BigInt(n) * TWO_POW_64];
  for (let i = 0; i < n; i += 3) {
    s = [
      add(s[0], inputs[i]),
      i + 1 < n ? add(s[1], inputs[i + 1]) : s[1],
      i + 2 < n ? add(s[2], inputs[i + 2]) : s[2],
      s[3],
    ];
    s = permute(s);
  }
  return s[0];
}

export const hash2 = (a: bigint, b: bigint) => hash([a, b]);
export const hash3 = (a: bigint, b: bigint, c: bigint) => hash([a, b, c]);
export const hash4 = (a: bigint, b: bigint, c: bigint, d: bigint) => hash([a, b, c, d]);
