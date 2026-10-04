// Append-only Merkle tree, depth 24, matching contracts/src/MerkleTree.sol and the circuit. Empty leaves are
// ZERO_LEAF = keccak256("opaque") mod field. Insertion costs 24 hashes, so a wallet can follow the pool's events.
import { hash2 } from "./poseidon2.ts";

export const DEPTH = 24;
export const ZERO_LEAF = 0x2fb59b7d0f99d0ee722695bf3dce13da949159db158e2304c1432d226b2fe50cn;

export const ZEROS: bigint[] = (() => {
  const z: bigint[] = [];
  let cur = ZERO_LEAF;
  for (let i = 0; i < DEPTH; i++) {
    z.push(cur);
    cur = hash2(cur, cur);
  }
  return z;
})();

export const EMPTY_ROOT: bigint = hash2(ZEROS[DEPTH - 1], ZEROS[DEPTH - 1]);

export class MerkleTree {
  // levels[0] holds the leaves, levels[DEPTH] holds the root once there is at least one leaf.
  private levels: bigint[][] = Array.from({ length: DEPTH + 1 }, () => []);

  get size(): number {
    return this.levels[0].length;
  }

  get root(): bigint {
    return this.size === 0 ? EMPTY_ROOT : this.levels[DEPTH][0];
  }

  insert(leaf: bigint): number {
    const index = this.size;
    if (BigInt(index) >= 1n << BigInt(DEPTH)) throw new Error("tree is full");
    this.levels[0].push(leaf);
    let node = leaf;
    let i = index;
    for (let l = 0; l < DEPTH; l++) {
      const sibling = i % 2 === 0 ? ZEROS[l] : this.levels[l][i - 1];
      node = i % 2 === 0 ? hash2(node, sibling) : hash2(sibling, node);
      i = Math.floor(i / 2);
      this.levels[l + 1][i] = node;
    }
    return index;
  }

  /** The 24 sibling hashes for the leaf at `index`, bottom to top, as the circuit expects. */
  path(index: number): bigint[] {
    if (index < 0 || index >= this.size) throw new Error("no such leaf");
    const out: bigint[] = [];
    let i = index;
    for (let l = 0; l < DEPTH; l++) {
      const sib = i ^ 1;
      out.push(sib < this.levels[l].length ? this.levels[l][sib] : ZEROS[l]);
      i = Math.floor(i / 2);
    }
    return out;
  }

  /** Recompute the root from a leaf, its index and its path. Same function as the circuit's `merkle_root`. */
  static rootFromPath(leaf: bigint, index: number, path: bigint[]): bigint {
    let node = leaf;
    let i = index;
    for (let l = 0; l < DEPTH; l++) {
      node = i % 2 === 0 ? hash2(node, path[l]) : hash2(path[l], node);
      i = Math.floor(i / 2);
    }
    return node;
  }
}
