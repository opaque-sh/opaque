import test from "node:test";
import assert from "node:assert/strict";
import { fromHex, toHex } from "./keccak.ts";
import { BASE_POINT, publicKey, x25519 } from "./x25519.ts";

test("RFC 7748 section 5.2, first vector", () => {
  const out = x25519(
    fromHex("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4"),
    fromHex("e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c"),
  );
  assert.equal(toHex(out), "0xc3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552");
});

test("RFC 7748 section 5.2, second vector", () => {
  const out = x25519(
    fromHex("4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d"),
    fromHex("e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493"),
  );
  assert.equal(toHex(out), "0x95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957");
});

test("RFC 7748 section 6.1, Diffie-Hellman", () => {
  const aliceSk = fromHex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a");
  const bobSk = fromHex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb");
  const alicePk = publicKey(aliceSk);
  const bobPk = publicKey(bobSk);
  assert.equal(toHex(alicePk), "0x8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a");
  assert.equal(toHex(bobPk), "0xde9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f");
  const shared = "0x4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742";
  assert.equal(toHex(x25519(aliceSk, bobPk)), shared);
  assert.equal(toHex(x25519(bobSk, alicePk)), shared);
});

test("the base point is u = 9", () => {
  assert.equal(BASE_POINT[0], 9);
  assert.equal(BASE_POINT.slice(1).every((b) => b === 0), true);
});
