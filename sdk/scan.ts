// Following the pool: rebuild the Merkle tree from `NoteAdded` events, and find the notes that are yours.
//
// A `NoteAdded(index, commitment, ciphertext)` event is emitted for every leaf. For each one, try to decrypt the
// ciphertext with your view key. If it opens, rebuild the commitment from the secrets and your own `opk`. Only a note
// whose commitment equals the event's is yours. A ciphertext that opens but does not match is junk and is ignored.
import { type AccountKeys } from "./keys.ts";
import { decryptNote } from "./encrypt.ts";
import { type Note, commitment, nullifier } from "./notes.ts";
import { MerkleTree } from "./tree.ts";

export type NoteAddedEvent = { index: number; commitment: bigint; ciphertext: Uint8Array };
export type OwnedNote = { note: Note; index: number; commitment: bigint; nullifier: bigint };

/** Events must arrive in leaf order, with no gaps. Throws if they do not, because the tree would be wrong. */
export function syncTree(events: NoteAddedEvent[], tree = new MerkleTree()): MerkleTree {
  for (const e of [...events].sort((a, b) => a.index - b.index)) {
    if (e.index < tree.size) continue; // already have it
    if (e.index !== tree.size) throw new Error(`missing leaf ${tree.size} before ${e.index}`);
    tree.insert(e.commitment);
  }
  return tree;
}

export async function findMyNotes(events: NoteAddedEvent[], keys: AccountKeys): Promise<OwnedNote[]> {
  const mine: OwnedNote[] = [];
  for (const e of events) {
    const s = await decryptNote(e.ciphertext, keys.viewSecret);
    if (!s) continue;
    const note: Note = { opk: keys.opk, rho: s.rho, r: s.r, assetId: s.assetId, amount: s.amount };
    let cm: bigint;
    try {
      cm = commitment(note);
    } catch {
      continue;
    }
    if (cm !== e.commitment) continue;
    mine.push({ note, index: e.index, commitment: cm, nullifier: nullifier(keys.nk, cm, BigInt(e.index)) });
  }
  return mine;
}
