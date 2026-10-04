// Account keys, derived from one wallet signature (decision 2026-10-04: no signature check inside the circuit).
//
//   The wallet signs a fixed message once. That signature is the seed:
//     master     = keccak256(signature)
//     nk         = keccak256("opaque/nk/v1" || master) mod field      (spends notes, derives nullifiers)
//     viewSecret = keccak256("opaque/view/v1" || master)               (decrypts incoming notes)
//   opk = Poseidon2(3, nk) is the part of an address that notes are made out to.
//
// This only works with wallets whose signatures are deterministic (RFC 6979: MetaMask, hardware wallets, most
// browser wallets). The app must sign twice and compare, and refuse a wallet that returns different signatures, or
// the user would lose their notes. Smart-contract wallets (ERC-1271) are not supported by this scheme.
//
// Whoever gets this signature gets the keys, so the message below says plainly what it is and the app must only
// ever ask for it on opaque.sh.
import { FIELD } from "./poseidon2.ts";
import { fromHex, keccak256, toHex } from "./keccak.ts";
import { ownerKey } from "./notes.ts";
import { publicKey } from "./x25519.ts";

export const KEY_VERSION = 1;

export function keyDerivationMessage(chainId: number): string {
  return [
    "Opaque account key",
    "",
    "Sign this to unlock your private notes on opaque.sh. The signature creates your Opaque keys on this device.",
    "It does not send a transaction and costs no gas.",
    "Only sign this on opaque.sh. Anyone who gets this signature can read and spend your private notes.",
    "",
    `Version: ${KEY_VERSION}`,
    `Chain: ${chainId}`,
  ].join("\n");
}

export type AccountKeys = {
  nk: bigint;
  opk: bigint;
  viewSecret: Uint8Array;
  viewPublic: Uint8Array;
};

const utf8 = (s: string) => new TextEncoder().encode(s);

function concat(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let off = 0;
  for (const p of parts) {
    out.set(p, off);
    off += p.length;
  }
  return out;
}

/** `signature` is the 65 byte (r, s, v) personal_sign result over `keyDerivationMessage`. */
export function deriveKeys(signature: Uint8Array): AccountKeys {
  if (signature.length !== 65) throw new Error("expected a 65 byte signature");
  const master = keccak256(signature);
  const nk = BigInt(toHex(keccak256(concat(utf8("opaque/nk/v1"), master)))) % FIELD;
  if (nk === 0n) throw new Error("derived a zero key, which is not allowed");
  const viewSecret = keccak256(concat(utf8("opaque/view/v1"), master));
  return { nk, opk: ownerKey(nk), viewSecret, viewPublic: publicKey(viewSecret) };
}

// ---------------------------------------------------------------- addresses

/** What someone gives you so you can be paid: your opk (to build the note) and your view key (to encrypt it). */
export type Address = { opk: bigint; viewPublic: Uint8Array };

/** Hex of 0x01 || opk (32 bytes) || view public key (32 bytes). */
export function encodeAddress(a: Address): string {
  const opk = fromHex("0x" + a.opk.toString(16).padStart(64, "0"));
  return toHex(concat(Uint8Array.of(KEY_VERSION), opk, a.viewPublic));
}

export function decodeAddress(s: string): Address {
  const b = fromHex(s);
  if (b.length !== 65 || b[0] !== KEY_VERSION) throw new Error("not an Opaque address");
  const opk = BigInt(toHex(b.slice(1, 33)));
  if (opk >= FIELD) throw new Error("not an Opaque address");
  return { opk, viewPublic: b.slice(33) };
}
