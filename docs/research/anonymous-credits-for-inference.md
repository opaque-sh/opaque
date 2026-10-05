# Anonymous credits for private AI payments

## Problem

The roadmap item is paying for AI inference from shrouded $OPA. The payment can be unlinkable on-chain, but the service still has to bill usage. If each request carries an account, the payment privacy is wasted. The service needs to meter without learning who is calling.

## Approach

1. **Issuance.** The user spends a note through an exit target that pays a gateway contract. The payment carries a blinded token request. The gateway's issuer signs it after seeing the payment event, and the user unblinds the result. The signed token cannot be linked to the payment that bought it.
2. **Redemption.** Each request presents a token. The service checks the signature and records the token as spent. This is the Privacy Pass architecture.
3. **Variable cost.** Inference cost is known only after the response. One-shot tokens force the user to buy many fixed-size tokens. Anonymous Credit Tokens let a client hold a balance, spend an amount per request, and receive a refund token for what was unused, without the service linking the requests. An IETF draft covers the protocol, and a separate rate-limited credential draft covers abuse control.

## Relation to the current design

The pool is unchanged. This is a new exit target plus an off-chain issuer. The spend and the issuance are tied by the blinded request, not by any account.

## What this does not hide

Payment privacy is not usage privacy. The gateway still sees prompts and the network address unless the transport hides them. The design needs oblivious transport (see the network metadata note) and, for strong claims, a provider that processes prompts in an attested enclave. The copy should say the payment cannot be traced to a wallet, nothing broader.

## Open questions

- The issuer holds the funds, so it can refuse to honour tokens. Can redemption be backed by an on-chain escrow with proofs of service?
- How is double spending prevented across several gateways without a shared database that links requests?
- Can an upstream provider accept these tokens directly, so Opaque is not a reseller?

## References

- RFC 9576, The Privacy Pass Architecture.
- IETF draft, Anonymous Credit Tokens: https://datatracker.ietf.org/doc/draft-schlesinger-cfrg-act/
- IETF draft, Anonymous Rate-Limited Credentials: https://datatracker.ietf.org/doc/draft-ietf-privacypass-arc-protocol/
