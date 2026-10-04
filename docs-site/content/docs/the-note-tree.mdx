---
title: The note tree
description: The Merkle tree that holds every commitment.
---

Every note's commitment is a leaf in one Merkle tree, shared by all assets.

| Property | Value |
| --- | --- |
| Depth | 24 |
| Capacity | 16,777,216 leaves |
| Hash | Poseidon2 over BN254 (state width 4) |
| Root history | The last 64 roots stay valid |
| Empty leaf | `keccak256("opaque")` reduced to the field |

The empty leaf is `0x2fb59b7d0f99d0ee722695bf3dce13da949159db158e2304c1432d226b2fe50c`. It is derived from a public string, so nobody can have chosen it to hide a trapdoor.

## Reference values

These are checked in the tests against values printed by the circuit.

| Tree | Root |
| --- | --- |
| Empty | `0x0ae5127e85ed8bc5bb8b69fdc41b3a35e0eea45834ac2b2b433975cc014ebb92` |
| One leaf | `0x28f0c18ed00c5247f6d5cd0fd3bcc1ce8d4984239fa55e9c4637b0955bf29c18` |

## Why a root history

A proof is built against a root. While you build one, other transactions add leaves, and the root moves. The pool accepts any of the last 64 roots, so slow proofs do not fail.

## Cost

Each insert hashes about 24 times at roughly 41,000 gas per hash, so about 1 million gas per leaf. A transaction that creates two notes is about 2 million gas before proof verification. Reducing this is on the list before launch.

## The hash is checked against the circuit

The on-chain hasher is generated from Barretenberg's BN254 Poseidon2 constants, the same ones Noir uses. The tests compare it with values printed by the circuit for the permutation, the two-input and four-input hashes, and the tree roots above.
