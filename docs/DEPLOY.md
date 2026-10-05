# Deploying the pool

One script deploys the hasher, the verifier and the pool: `contracts/script/DeployPool.s.sol`. It was run end to end
against a local chain and on Robinhood Chain mainnet with a throwaway token.

## Settings baked into the script

| Setting | Value |
| --- | --- |
| Unshroud fee | 0.3% of each exit |
| Deposit cap | starts at 50,000,000 tokens (5% of a 1B supply), rises by 5,000,000 (0.5%) every 7 days, ceiling 100,000,000 (10%) |
| Guardian | the deployer, or `GUARDIAN` if set. It can only pause new shrouds |

All of it is fixed once deployed. Change it in the script before you run it, not after.

## Order for the real launch

1. Launch $OPA on Pons (ETH pair, buyback off, creator tax as decided). Read `getLaunchedToken(token)` and check `pairToken` is the zero address and `buybackEnabled` is false.
2. Deploy the pool with that token. The deposit schedule starts at this moment.
3. Deploy the harvester with `contracts/script/DeployHarvester.s.sol` (`docs/HARVESTER.md`).
4. After the 12 to 24 hour manual period, move the Pons creator fee recipient to the harvester.

## Running it

Use a wallet made for this and funded with a little ETH. Keep the key in a Foundry keystore, never in a file or a chat:

```
cast wallet import opaque-deployer --interactive
TOKEN=0x... forge script contracts/script/DeployPool.s.sol \
  --rpc-url https://rpc.mainnet.chain.robinhood.com --account opaque-deployer --broadcast
```

It prints the three addresses and the pool's settings. Deploying costs roughly 18 million gas in Foundry's accounting,
mostly the verifier, so check the chain's gas price first. Run it without `--broadcast` first to simulate.

The verifier is 24,489 bytes against a 24,576 byte limit. If the chain turns out to enforce a smaller limit, the
verifier deploy fails and the whole script reverts.

The addresses of what has been deployed are recorded in `docs/DEPLOYMENTS.md`.
