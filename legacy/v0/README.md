# v0 (legacy reference)

These are the v0 contracts that Opaque is derived from. They are kept for reference only.

- They are not compiled by this repo's Foundry config.
- They are not audited as part of Opaque.
- They are single-asset. Opaque's pool is multi-asset, see `docs/DESIGN.md`.

Files:

- `PrivateVault.sol`: the vault, note tree, ERC-4337 account and private-sale settlement.
- `FeeHarvesterV2.sol`: the Pons creator-fee splitter, gas top-up and buyback keeper.

See `docs/REVIEW_NOTES.md` for flags raised while reading them.
