# Deployments

Robinhood Chain mainnet, chain id 4663. Explorer: https://robin.etherscan.io

## $OPA pool

| Item | Address |
| --- | --- |
| $OPA token (Pons v2) | `0x01f7748D1A3543ad3f9e71B2fbDc10c00688E7F5` |
| OpaquePool | `0xC4dd454637180954857E75DA595645145FCE189B` |
| HonkVerifier | `0x01cCac633260407E9e8a0a732C4Fcded527A5E7a` |
| Poseidon2Hasher | `0xF4a67dDD3A94E27BA0e4c8955bC8852F60DA3E01` |
| Guardian | `0x144Ed37641636B44918Fa2A0A2057AA268D7Fd6b` |

- Pool deployed at block 80820391 (verifier at block 80820372). Use 80820391 as the first block when scanning for events.
- Pool launch time (unix): 1791206829. The deposit cap schedule starts here.
- Unshroud fee: 0.3% of each exit.
- Deposit cap: starts at 50,000,000 tokens, rises by 5,000,000 every 7 days, ceiling 100,000,000.
- The guardian can only pause new shrouds. It cannot touch funds, change settings or upgrade anything.

## Harvester

Not deployed yet. See `docs/HARVESTER.md` and `contracts/script/DeployHarvester.s.sol`.
