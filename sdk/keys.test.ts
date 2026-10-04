import test from "node:test";
import assert from "node:assert/strict";
import { CIPHERTEXT_LEN, decryptNote, encryptNote } from "./encrypt.ts";
import { decodeAddress, deriveKeys, encodeAddress, keyDerivationMessage } from "./keys.ts";
import { type Note, commitment, nullifier } from "./notes.ts";
import { findMyNotes, syncTree } from "./scan.ts";
import { MerkleTree } from "./tree.ts";

const sig = (fill: number) => new Uint8Array(65).fill(fill);

test("keys are deterministic and differ per signature", () => {
  const a = deriveKeys(sig(1));
  const b = deriveKeys(sig(1));
  const c = deriveKeys(sig(2));
  assert.equal(a.nk, b.nk);
  assert.deepEqual(a.viewPublic, b.viewPublic);
  assert.notEqual(a.nk, c.nk);
  assert.notDeepEqual(a.viewPublic, c.viewPublic);
  assert.notEqual(a.opk, c.opk);
});

test("the message names the chain and where to sign", () => {
  const m = keyDerivationMessage(4663);
  assert.ok(m.includes("Chain: 4663") && m.includes("opaque.sh") && m.includes("no gas"));
  assert.notEqual(keyDerivationMessage(1), m);
});

test("address round trip", () => {
  const k = deriveKeys(sig(3));
  const a = decodeAddress(encodeAddress({ opk: k.opk, viewPublic: k.viewPublic }));
  assert.equal(a.opk, k.opk);
  assert.deepEqual(a.viewPublic, k.viewPublic);
  assert.throws(() => decodeAddress("0x1234"), /not an Opaque address/);
});

test("encrypt then decrypt returns the secrets", async () => {
  const k = deriveKeys(sig(4));
  const secrets = { rho: 123n, r: 456n, amount: 10n ** 27n, assetId: 1n };
  const ct = await encryptNote(secrets, k.viewPublic);
  assert.equal(ct.length, CIPHERTEXT_LEN);
  assert.deepEqual(await decryptNote(ct, k.viewSecret), secrets);
});

test("someone else cannot decrypt, and an altered ciphertext is rejected", async () => {
  const k = deriveKeys(sig(5));
  const other = deriveKeys(sig(6));
  const ct = await encryptNote({ rho: 1n, r: 2n, amount: 3n, assetId: 1n }, k.viewPublic);
  assert.equal(await decryptNote(ct, other.viewSecret), null);
  for (const pos of [0, 5, 40, 60, CIPHERTEXT_LEN - 1]) {
    const bad = Uint8Array.from(ct);
    bad[pos] ^= 1;
    assert.equal(await decryptNote(bad, k.viewSecret), null, `byte ${pos}`);
  }
  assert.equal(await decryptNote(ct.slice(1), k.viewSecret), null);
});

test("two encryptions of the same note differ", async () => {
  const k = deriveKeys(sig(7));
  const s = { rho: 1n, r: 2n, amount: 3n, assetId: 1n };
  const a = await encryptNote(s, k.viewPublic);
  const b = await encryptNote(s, k.viewPublic);
  assert.notDeepEqual(a, b);
});

test("scan: finds only my notes, and the tree follows the events", async () => {
  const me = deriveKeys(sig(8));
  const you = deriveKeys(sig(9));
  const mk = (keys: typeof me, rho: bigint, amount: bigint): Note => ({ opk: keys.opk, rho, r: rho + 1n, assetId: 1n, amount });
  const notes = [mk(me, 10n, 5n), mk(you, 11n, 6n), mk(me, 12n, 7n)];
  const events = [];
  for (const [i, n] of notes.entries()) {
    const owner = i === 1 ? you : me;
    events.push({
      index: i,
      commitment: commitment(n),
      ciphertext: await encryptNote({ rho: n.rho, r: n.r, amount: n.amount, assetId: 1n }, owner.viewPublic),
    });
  }
  // a note that decrypts but whose commitment does not match must be ignored
  events.push({
    index: 3,
    commitment: 999n,
    ciphertext: await encryptNote({ rho: 1n, r: 1n, amount: 1n, assetId: 1n }, me.viewPublic),
  });

  const mine = await findMyNotes(events, me);
  assert.deepEqual(mine.map((m) => m.index), [0, 2]);
  assert.equal(mine[0].nullifier, nullifier(me.nk, commitment(notes[0]), 0n));

  const tree = syncTree(events);
  assert.equal(tree.size, 4);
  const direct = new MerkleTree();
  for (const e of events) direct.insert(e.commitment);
  assert.equal(tree.root, direct.root);
  assert.throws(() => syncTree([events[0], events[2]]), /missing leaf 1/);
});

test("scan: a shroud note is found even if the wallet predicted the wrong share count", async () => {
  const me = deriveKeys(sig(10));
  // the wallet predicted 1000 shares, but another deposit landed first and the pool minted 990
  const minted = 990n;
  const note: Note = { opk: me.opk, rho: 5n, r: 6n, assetId: 1n, amount: minted };
  const event = {
    index: 0,
    commitment: commitment(note),
    ciphertext: await encryptNote({ rho: 5n, r: 6n, amount: 1000n, assetId: 1n }, me.viewPublic),
  };
  assert.equal((await findMyNotes([event], me)).length, 0, "without the minted figure the note is not found");
  const found = await findMyNotes([{ ...event, shroudedShares: minted }], me);
  assert.equal(found.length, 1);
  assert.equal(found[0].note.amount, minted);
});
