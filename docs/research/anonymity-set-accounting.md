# Anonymity-set accounting

## Problem

"Anonymity set size" is usually quoted as a headcount: the number of deposits in the pool. It is the wrong number. What matters is how many deposits are consistent with a particular exit once an adversary applies everything it can observe: amount, timing, root choice, gas payer, address reuse. That number is usually orders of magnitude smaller than the headcount, and nobody tells the user.

## Proposed design

Ship the measurement with the product.

1. **Effective set as entropy.** For a planned exit, the wallet computes the posterior probability that each candidate shroud is the source, using the same heuristics an attacker would. The reported figure is the Shannon entropy of that distribution, expressed as an effective set size `2^H`.
2. **Counterfactual planning.** The wallet shows how the figure changes with delay, with amount grid choice, and with using a relayer, so the user sees the privacy cost of impatience in numbers.
3. **Pool-wide dashboard.** A public page reports, per day, the median effective set across exits as computed by the simulator over on-chain data. It is a falsifiable privacy claim: anyone can rerun it.
4. **Regression gating.** Each protocol change (amount grid, epochs, churn) must raise or hold the dashboard figure on replayed historical data before it ships.

## Why this is the point

A privacy protocol that cannot state, with a reproducible measurement, how private an exit was is asking for trust. This puts a number on it and puts the method in the repo.

## Open questions

- Which heuristics belong in the baseline attacker? A published, versioned list, extended as new attacks appear, makes the metric comparable over time.
- Does showing the number change user behaviour enough to help, or does it push everyone to the same delay and create a new fingerprint? The simulator can test this with agent-based user models before the feature ships.
