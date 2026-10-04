# Trust

## What we will not do

- No admin keys over funds. The core is immutable.
- No upgradeable proxies on the pool.
- No pausing of withdrawals. The guardian can only pause new deposits.
- No hidden team allocation or unlabeled team activity.
- No claim that Opaque hides deposits or withdrawals. Shield and exit amounts and addresses are public. It hides what happens between them.
- No yield promises. Yield comes from fees and can be zero.

## The fee harvester

The pool pays nobody. Trade fees reach it only through the harvester (`docs/HARVESTER.md`), which is meant to be $OPA's Pons creator fee recipient.

- The harvester's owner can change the team's payout address and propose a successor, which becomes the fee recipient after 24 public hours. The owner can renounce, which removes that path.
- Pons' own takeover process can also move the fee recipient, and we cannot stop it.
- The harvester is unaudited and has not run against the live Pons contracts.
- Fees collected by a team wallet before the handover are handled by hand and can be donated to the pool later.

## Invariants (draft, to be tested)

1. The sum of unspent note value never exceeds the pool's backing.
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
