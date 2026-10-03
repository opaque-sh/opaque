# Trust

## What we will not do

- No admin keys over funds. The core is immutable.
- No upgradeable proxies on the pool.
- No pausing of withdrawals. The guardian can only pause new deposits.
- No hidden team allocation or unlabeled team activity.
- No claim that Opaque hides what you send. It hides who paid, not what you send.
- No yield promises. Yield comes from fees and can be zero.

## Invariants (draft, to be tested)

1. For each asset, the sum of unspent note value never exceeds the pool's backing of that asset.
2. A nullifier can be spent once.
3. Only a known root can be spent against.
4. Exit amount never exceeds the value of the spent notes minus fees.
5. The guardian cannot move or freeze funds.

These become Foundry invariant tests under `contracts/test/`.

## Stage caps

Deposit caps rise on a fixed on-chain schedule. The schedule is set at deployment and cannot be changed. Numbers to be decided before launch.

## Bounty

Public and scaling with pool size. See `SECURITY.md`.

## Honest labeling

Any seeded liquidity, team deposit or test activity is labeled as such on the site and dashboard.
