#!/usr/bin/env bash
# Make the proof for the end-to-end scenario (circuits/pool/e2e.toml, written by `npm run e2e:gen` in sdk/) and copy
# the proof and its public inputs into contracts/test/fixtures/, where OpaquePoolE2E.t.sol reads them.
#
# Same tools and flags as build_verifier.sh. NOT run end to end by the author before the first GitHub run.
#
# Usage (from repo root):
#   ./circuits/pool/scripts/prove_e2e.sh
set -euo pipefail

cd "$(dirname "$0")/.."

echo "== compile and solve the e2e witness"
nargo compile
nargo execute --prover-name e2e e2e_w

OUT=target/bb_e2e
mkdir -p "$OUT"

echo "== verification key"
bb write_vk -s ultra_honk -b target/opaque_pool.json -o "$OUT" --oracle_hash keccak

echo "== prove"
bb prove -s ultra_honk -b target/opaque_pool.json -w target/e2e_w.gz -k "$OUT/vk" -o "$OUT" --oracle_hash keccak

echo "== verify natively"
bb verify -s ultra_honk -k "$OUT/vk" -p "$OUT/proof" -i "$OUT/public_inputs" --oracle_hash keccak

FIX=../../contracts/test/fixtures
cp "$OUT/proof" "$FIX/e2e_proof.bin"
cp "$OUT/public_inputs" "$FIX/e2e_public_inputs.bin"
echo "done. Wrote $FIX/e2e_proof.bin and $FIX/e2e_public_inputs.bin"
echo "Then run: forge test --match-path contracts/test/OpaquePoolE2E.t.sol -vv"
