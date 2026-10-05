# Relayers and shielded paymasters

## Problem

A user who unshrouds to a fresh address has no ETH there, and paying gas from a linked wallet defeats the purpose. A relayer submits the transaction and is paid from the exit.

## What exists

The fee to the relayer is paid in shares inside the proof's external data, and the external data hash binds the recipient, the caller, the fee and the data. Because the caller is bound, a relayer cannot swap the recipient or fee, and another party cannot replay a copied proof under their own address.

## Directions

1. **A permissionless relayer market.** Many relayers quote fees. Users send the proof over an oblivious channel (see the network metadata note) and any relayer can submit. The bound caller field means whichever relayer was named is the one that can submit.
2. **A gas drip exit target.** A small part of an exit is swapped to ETH and sent to the destination, so a fresh address can pay its own first transaction. No relayer is needed for that first step.
3. **ERC-4337 paymasters.** A paymaster sponsors a UserOperation that calls the pool and is repaid from the fee. The constraint is validation: ERC-7562 limits what a paymaster may do during validation, and verifying a proof costs substantial gas. Postponing the check to the execution phase shifts the risk to the paymaster, which must price it.
4. **Fee shaping.** Quote fees as a fixed amount of $OPA so the fee does not reveal how much the exit is.

## What a relayer learns

The recipient address, the amount and the requester's network address. A relayer is a trusted observer for that transaction, so hop count and transport matter as much as the contract design.

## Open questions

- How are relayers kept honest about censoring, and how is a user protected if the chosen relayer disappears before submitting?
- Can the paymaster's risk be bounded without making it a trusted operator?
- Is a gas drip worth the extra swap and the extra on-chain footprint?

## References

- ERC-4337, Account Abstraction.
- ERC-7562, Account Abstraction Validation Scope Rules.
