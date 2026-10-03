#!/usr/bin/env bash
# Build the proof system for the Opaque pool circuit and write the Solidity verifier.
#
# Needs: nargo 1.0.0-beta.11 and bb (Barretenberg) 1.2.1 on PATH, plus internet access, because bb downloads the
# BN254 trusted setup (CRS) on first run.
#
# NOTE: written and checked against the bb 1.2.1 command line, but NOT run end to end by the author. The CRS
# download was blocked in the authoring environment. Run it, read the output, and fix flags if bb has changed.
#
# Usage (from repo root):
#   ./circuits/pool/scripts/build_verifier.sh
set -euo pipefail

cd "$(dirname "$0")/.."

echo "== compile and solve the example witness"
nargo compile
nargo execute            # uses Prover.toml, writes target/opaque_pool.gz

mkdir -p target/bb

echo "== verification key (keccak oracle, for on-chain verification)"
bb write_vk -s ultra_honk -b target/opaque_pool.json -o target/bb --oracle_hash keccak

echo "== prove"
bb prove -s ultra_honk -b target/opaque_pool.json -w target/opaque_pool.gz \
  -k target/bb/vk -o target/bb --oracle_hash keccak

echo "== verify natively"
bb verify -s ultra_honk -k target/bb/vk -p target/bb/proof -i target/bb/public_inputs --oracle_hash keccak

echo "== write Solidity verifier"
bb write_solidity_verifier -s ultra_honk -k target/bb/vk -o ../../contracts/src/HonkVerifier.sol

echo "done. Next: deploy HonkVerifier and pass its address to OpaquePool as the verifier."
echo "The proof is in circuits/pool/target/bb/proof and its public inputs in public_inputs."
echo "The public inputs must match OpaquePool.publicInputs() order, see circuits/README.md."
