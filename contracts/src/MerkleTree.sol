// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHasher} from "./interfaces/IHasher.sol";

/// @title MerkleTree
/// @notice Append-only incremental Merkle tree with a ring buffer of recent roots.
/// @dev Depth 24, 64 roots of history. Empty leaves are `ZERO_LEAF`, a nothing-up-my-sleeve value, so that an empty
///      tree has a non-zero root and a zero commitment can never be confused with an empty slot. The circuit must use
///      the same `ZERO_LEAF` and the same hash.
abstract contract MerkleTree {
    uint256 internal constant FIELD_SIZE =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    uint256 public constant DEPTH = 24;
    uint256 public constant ROOT_HISTORY = 64;

    /// @notice keccak256("opaque") reduced into the field.
    uint256 public constant ZERO_LEAF = uint256(keccak256("opaque")) % FIELD_SIZE;

    IHasher public immutable hasher;

    uint32 public nextIndex;
    uint32 public rootIndex;
    uint256 public currentRoot;

    uint256[24] internal filledSubtrees;
    uint256[24] internal zeros;
    uint256[64] internal roots;

    error TreeFull();

    constructor(IHasher hasher_) {
        hasher = hasher_;
        uint256 z = ZERO_LEAF;
        for (uint256 i = 0; i < DEPTH; i++) {
            zeros[i] = z;
            filledSubtrees[i] = z;
            z = hasher_.hash2(z, z);
        }
        currentRoot = z;
        roots[0] = z;
    }

    /// @notice True if `root` is one of the last 64 roots (or the empty-tree root).
    function isKnownRoot(uint256 root) public view virtual returns (bool) {
        if (root == 0) return false;
        for (uint256 i = 0; i < ROOT_HISTORY; i++) {
            if (roots[i] == root) return true;
        }
        return false;
    }

    /// @dev Insert one leaf. Does not record a root, so callers can insert several leaves and record once.
    function _insertLeaf(uint256 leaf) internal returns (uint32 index) {
        index = nextIndex;
        if (uint256(index) >= (uint256(1) << DEPTH)) revert TreeFull();

        uint32 cur = index;
        uint256 node = leaf;
        for (uint256 i = 0; i < DEPTH; i++) {
            if (cur & 1 == 0) {
                filledSubtrees[i] = node;
                node = hasher.hash2(node, zeros[i]);
            } else {
                node = hasher.hash2(filledSubtrees[i], node);
            }
            cur >>= 1;
        }
        currentRoot = node;
        nextIndex = index + 1;
    }

    /// @dev Record `currentRoot` in the history ring.
    function _recordRoot() internal {
        uint32 next = (rootIndex + 1) % uint32(ROOT_HISTORY);
        rootIndex = next;
        roots[next] = currentRoot;
    }
}
