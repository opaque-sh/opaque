#!/usr/bin/env bash
# Fetches the pinned dependencies into lib/ and builds the Uniswap v4 PoolManager that the harvester tests deploy.
# Run once from the repo root. Safe to run again.
set -euo pipefail

FORGE_STD_REF="${FORGE_STD_REF:-HEAD}"
V4_CORE_REF="46c6834698c48bc4a463a86d8420f4eb1d7f3b75"
SOLMATE_REF="4b47a19038b798b4a33d9749d25e570443520647"

clone_at() { # url dir ref
  if [ ! -d "$2/.git" ]; then
    mkdir -p "$2" && git -C "$2" init -q && git -C "$2" remote add origin "$1"
  fi
  if [ "$3" = "HEAD" ]; then
    git -C "$2" fetch -q --depth 1 origin HEAD && git -C "$2" checkout -q FETCH_HEAD
  else
    git -C "$2" fetch -q --depth 1 origin "$3" && git -C "$2" checkout -q "$3"
  fi
}

clone_at https://github.com/foundry-rs/forge-std lib/forge-std "$FORGE_STD_REF"
clone_at https://github.com/Uniswap/v4-core lib/v4-core "$V4_CORE_REF"
clone_at https://github.com/transmissions11/solmate lib/solmate "$SOLMATE_REF"

# v4-core builds on its own settings (via-ir). Point its libs at ours so it needs no submodules.
mkdir -p lib/v4-core/lib
for d in forge-std solmate; do
  [ -e "lib/v4-core/lib/$d" ] || ln -s "../../$d" "lib/v4-core/lib/$d"
done

(cd lib/v4-core && forge build src/PoolManager.sol)
echo "ok: lib/v4-core/out/PoolManager.sol/PoolManager.json"
