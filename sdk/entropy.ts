// Mixes user-supplied entropy (pointer movement and timing) into note secrets.
//
// The result is SHA-256 over: the CSPRNG output, then the pointer samples. Because the CSPRNG output is always
// included, the secret is at least as unpredictable as crypto.getRandomValues alone. The ritual can add to that
// but can never reduce it, even if the pointer samples are scripted or predictable.

export type PointerSample = { x: number; y: number; t: number };

const FIELD =
  21888242871839275222246405745257275088548364400416034343698204186575808495617n; // BN254 scalar field

export function csprng(bytes: number): Uint8Array {
  const out = new Uint8Array(bytes);
  globalThis.crypto.getRandomValues(out);
  return out;
}

function encodeSamples(samples: PointerSample[]): Uint8Array {
  // 3 x float64 per sample, little endian. Only the last 4096 samples are used.
  const used = samples.slice(-4096);
  const buf = new ArrayBuffer(used.length * 24);
  const view = new DataView(buf);
  used.forEach((s, i) => {
    view.setFloat64(i * 24, s.x, true);
    view.setFloat64(i * 24 + 8, s.y, true);
    view.setFloat64(i * 24 + 16, s.t, true);
  });
  return new Uint8Array(buf);
}

async function sha256(...parts: Uint8Array[]): Promise<Uint8Array> {
  const total = parts.reduce((n, p) => n + p.length, 0);
  const joined = new Uint8Array(total);
  let off = 0;
  for (const p of parts) {
    joined.set(p, off);
    off += p.length;
  }
  return new Uint8Array(await globalThis.crypto.subtle.digest("SHA-256", joined));
}

/** 32 bytes of seed material: CSPRNG output mixed with the user's samples. */
export async function mixEntropy(samples: PointerSample[], label: string): Promise<Uint8Array> {
  const label8 = new TextEncoder().encode(label);
  return sha256(csprng(32), encodeSamples(samples), label8);
}

/** A field element (below the BN254 scalar modulus) from mixed entropy. Uses 64 bytes to keep bias negligible. */
export async function mixedFieldElement(samples: PointerSample[], label: string): Promise<bigint> {
  const a = await mixEntropy(samples, label + ":a");
  const b = await mixEntropy(samples, label + ":b");
  let n = 0n;
  for (const byte of [...a, ...b]) n = (n << 8n) | BigInt(byte);
  return n % FIELD;
}

/** How many distinct, spread-out samples have been gathered, as 0..1. Drives the progress meter only. */
export function progress(samples: PointerSample[], target = 160): number {
  let kept = 0;
  let lx = -1e9;
  let ly = -1e9;
  for (const s of samples) {
    if (Math.abs(s.x - lx) + Math.abs(s.y - ly) >= 6) {
      kept++;
      lx = s.x;
      ly = s.y;
    }
  }
  return Math.min(1, kept / target);
}
