---
title: The pool and holder yield
description: How the pool holds $OPA, and how shrouded $OPA accrues value.
---

One contract, `OpaquePool`, holds $OPA and one note tree. $OPA is the only asset the pool accepts. ETH and other tokens are not accepted: ETH sent to the pool is rejected.

Every note still carries an asset id inside its commitment, always 1 here. The field is kept so a future pool version could add assets without a new circuit.

## $OPA notes

Shrouding $OPA pulls tokens into the pool and mints shares at the current price. `backing` is the tokens held for all notes. `units` is the total shares.

A donation adds to the backing without minting shares. Every note's shares are then worth more tokens. Exiting redeems shares at the current price. The unshroud fee also stays in the backing, so it goes to everyone still shrouded.

## Why only private holders earn

Yield accrues to shares, and shares exist only inside notes. Tokens in a public wallet are not shares. That is the whole mechanism: to earn, shroud.

## Immutable configuration

The verifier, the $OPA address, the guardian, the unshroud fee percentage and the deposit schedule are set in the constructor. None can be changed. The pool has no fee recipient address: it never sends fees to anyone.
