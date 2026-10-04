// Note encryption: so the person a note is made out to can find it and learn its secrets (rho, r, amount, asset).
//
//   shared = X25519(ephemeral secret, receiver view key)
//   key    = HKDF-SHA256(ikm = shared, salt = ephemeral public || receiver view key, info = "opaque/note/v1")
//   box    = AES-256-GCM(key, random nonce, plaintext, aad = version byte)
//
// Layout: version (1) | ephemeral public (32) | nonce (12) | ciphertext and tag (plaintext + 16).
// Plaintext: rho (32) | r (32) | amount (16) | asset id (32), big endian.
//
// Standard, classical encryption by decision (2026-10-04). A hybrid post-quantum layer can be added later as a new
// version byte, because the pool treats the ciphertext as opaque bytes. A passive observer who records ciphertexts
// today could read them with a future quantum computer, so these notes are not quantum-safe.
import { type Note, MAX_AMOUNT } from "./notes.ts";
import { FIELD } from "./poseidon2.ts";
import { fromHex, toHex } from "./keccak.ts";
import { BASE_POINT, publicKey, x25519 } from "./x25519.ts";

const VERSION = 1;
const PLAINTEXT_LEN = 32 + 32 + 16 + 32;
export const CIPHERTEXT_LEN = 1 + 32 + 12 + PLAINTEXT_LEN + 16;

const subtle = globalThis.crypto.subtle;
const utf8 = (s: string) => new TextEncoder().encode(s);

function bigToBytes(v: bigint, len: number): Uint8Array {
  const out = new Uint8Array(len);
  let x = v;
  for (let i = len - 1; i >= 0; i--) {
    out[i] = Number(x & 0xffn);
    x >>= 8n;
  }
  if (x !== 0n) throw new Error("value too large");
  return out;
}

const bytesToBig = (b: Uint8Array): bigint => BigInt(toHex(b));

async function deriveKey(shared: Uint8Array, ephPublic: Uint8Array, recvPublic: Uint8Array): Promise<CryptoKey> {
  if (shared.every((b) => b === 0)) throw new Error("bad key exchange");
  const ikm = await subtle.importKey("raw", shared, "HKDF", false, ["deriveKey"]);
  const salt = new Uint8Array(64);
  salt.set(ephPublic, 0);
  salt.set(recvPublic, 32);
  return subtle.deriveKey(
    { name: "HKDF", hash: "SHA-256", salt, info: utf8("opaque/note/v1") },
    ikm,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"],
  );
}

export type NoteSecrets = { rho: bigint; r: bigint; amount: bigint; assetId: bigint };

/** Encrypt the secrets of a note to `recvPublic` (the receiver's view public key). */
export async function encryptNote(secrets: NoteSecrets, recvPublic: Uint8Array): Promise<Uint8Array> {
  if (secrets.amount < 0n || secrets.amount > MAX_AMOUNT) throw new Error("amount out of range");
  if (secrets.rho >= FIELD || secrets.r >= FIELD) throw new Error("rho and r must be field elements");
  const ephSecret = new Uint8Array(32);
  globalThis.crypto.getRandomValues(ephSecret);
  const ephPublic = publicKey(ephSecret);
  const key = await deriveKey(x25519(ephSecret, recvPublic), ephPublic, recvPublic);

  const plaintext = new Uint8Array(PLAINTEXT_LEN);
  plaintext.set(bigToBytes(secrets.rho, 32), 0);
  plaintext.set(bigToBytes(secrets.r, 32), 32);
  plaintext.set(bigToBytes(secrets.amount, 16), 64);
  plaintext.set(bigToBytes(secrets.assetId, 32), 80);

  const nonce = new Uint8Array(12);
  globalThis.crypto.getRandomValues(nonce);
  const box = new Uint8Array(
    await subtle.encrypt({ name: "AES-GCM", iv: nonce, additionalData: Uint8Array.of(VERSION) }, key, plaintext),
  );
  const out = new Uint8Array(CIPHERTEXT_LEN);
  out[0] = VERSION;
  out.set(ephPublic, 1);
  out.set(nonce, 33);
  out.set(box, 45);
  return out;
}

/** Returns the secrets, or null if this ciphertext is not for the holder of `viewSecret` (or was altered). */
export async function decryptNote(ciphertext: Uint8Array, viewSecret: Uint8Array): Promise<NoteSecrets | null> {
  if (ciphertext.length !== CIPHERTEXT_LEN || ciphertext[0] !== VERSION) return null;
  const ephPublic = ciphertext.slice(1, 33);
  const nonce = ciphertext.slice(33, 45);
  const box = ciphertext.slice(45);
  try {
    const recvPublic = publicKey(viewSecret);
    const key = await deriveKey(x25519(viewSecret, ephPublic), ephPublic, recvPublic);
    const plaintext = new Uint8Array(
      await subtle.decrypt({ name: "AES-GCM", iv: nonce, additionalData: Uint8Array.of(VERSION) }, key, box),
    );
    return {
      rho: bytesToBig(plaintext.slice(0, 32)),
      r: bytesToBig(plaintext.slice(32, 64)),
      amount: bytesToBig(plaintext.slice(64, 80)),
      assetId: bytesToBig(plaintext.slice(80, 112)),
    };
  } catch {
    return null;
  }
}

export { BASE_POINT, fromHex };
