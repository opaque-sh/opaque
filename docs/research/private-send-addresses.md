# Payment addresses and private send

## Problem

Private sending moves value between shrouded balances. The sender needs the recipient's address, and observers must not be able to link two payments to the same person.

## What the note format already gives

A note's commitment hides the owner's key. The ciphertext for the recipient uses a fresh ephemeral key per note. Two payments to the same address therefore look unrelated on-chain, even if the address is reused. The remaining risks are discovery, key substitution and linkability between senders who share addresses.

## Directions

1. **Diversified addresses.** The recipient derives many addresses from one key, each distinguishable only to the recipient. A sender who holds two addresses cannot tell they belong to the same person, and an address can be retired without changing keys. The circuit proves ownership of a derived key.
2. **A registry for payment addresses.** Following ERC-6538, a contract maps names or accounts to a payment address, with a signature binding the owner to avoid substitution.
3. **View tags** on every note, shared with the scanning note, so discovery stays cheap.
4. **KEM-based addresses for post-quantum safety.** The elliptic-curve exchange is the part a quantum computer breaks. Replace or pair it with a key encapsulation mechanism. ML-KEM-768 ciphertexts are 1,088 bytes, so each output gains roughly a kilobyte of calldata, which matters on an L2 where calldata is the main cost.
5. **Payment requests.** A signed request carrying an amount, an asset and an expiry, so the payer does not retype anything.

## Open questions

- Should addresses be single-use by default, with a registry only for people who opt in?
- What does a registry reveal about who is reachable?
- Can the post-quantum ciphertext overhead be amortised, for example one encapsulation shared by both outputs of a transaction?

## References

- ERC-5564, Stealth Addresses.
- ERC-6538, Stealth Meta-Address Registry.
