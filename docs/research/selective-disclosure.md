# Selective disclosure and association sets

## Problem

Pools get tainted. An exchange or a service looking at an incoming transfer from a privacy pool cannot tell whether the funds are clean. Users who have nothing to hide have no way to prove it without revealing everything.

## Approach: association sets

The Privacy Pools proposal lets a user prove, in zero knowledge, that their deposit belongs to an association set that excludes known-bad deposits, without revealing which deposit is theirs. Association set providers publish sets. Users choose which sets to prove membership in. The pool itself stays permissionless and does not depend on any provider.

## The difficulty in a transferable pool

Privacy Pools applies to a deposit and a withdrawal. In a pool with private transfers, a note's history can pass through several hands, and the ancestry of the note is hidden. One option is lane-tagged notes:

- A note carries a lane identifier inside its commitment.
- A shroud into a lane is checked against that lane's association set at deposit time.
- The circuit enforces that outputs inherit the lane of their inputs. Mixing lanes yields the weaker lane.
- Exits can prove the lane to a counterparty.

The cost is that lanes split the anonymity set. A user pays for the proof of cleanliness with a smaller crowd.

## Related: view keys and date ranges

Epoch keys, already on the roadmap, give disclosure of activity for a date range to an auditor without exposing anything outside it. That is a user-controlled disclosure, separate from association sets.

## Open questions

- Is a lane worth the crowd it takes away, and how many lanes before the sets are too small?
- Who publishes association sets, and how do users avoid trusting one provider?
- Can a proof of ancestry be kept bounded in circuit size across many hops, using recursion?

## References

- Buterin, Illum, Nadler, Schär, Soleimani, "Blockchain privacy and regulatory compliance: Towards a practical equilibrium": https://www.sciencedirect.com/science/article/pii/S2096720923000519
