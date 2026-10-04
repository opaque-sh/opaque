import test from "node:test";
import assert from "node:assert/strict";
import { keccak256, toHex, fromHex } from "./keccak.ts";
import { FIELD } from "./poseidon2.ts";

const utf8 = (s: string) => new TextEncoder().encode(s);

test("keccak256 of the empty string", () => {
  assert.equal(toHex(keccak256(new Uint8Array())), "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470");
});

test("keccak256 of 'abc'", () => {
  assert.equal(toHex(keccak256(utf8("abc"))), "0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45");
});

test("keccak256 across a block boundary (136 and 200 bytes)", () => {
  // values from `cast keccak` over 136 and 200 'a' characters
  assert.equal(toHex(keccak256(utf8("a".repeat(136)))), KECCAK_A136);
  assert.equal(toHex(keccak256(utf8("a".repeat(200)))), KECCAK_A200);
});

test("ZERO_LEAF is keccak256('opaque') mod the field", () => {
  const v = BigInt(toHex(keccak256(utf8("opaque")))) % FIELD;
  assert.equal(v, 0x2fb59b7d0f99d0ee722695bf3dce13da949159db158e2304c1432d226b2fe50cn);
});

test("hex round trip", () => {
  assert.equal(toHex(fromHex("0x00ff10")), "0x00ff10");
});

const KECCAK_A136 = "0xa6c4d403279fe3e0af03729caada8374b5ca54d8065329a3ebcaeb4b60aa386e";
const KECCAK_A200 = "0x96ea54061def936c4be90b518992fdc6f12f535068a256229aca54267b4d084d";
