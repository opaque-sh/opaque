# Attested execution verified by zero-knowledge proofs

## Problem

Zero-knowledge proofs are slow for complex logic, and trusted execution environments are fast but must be trusted. Chains that accept raw TEE attestations also inherit every attestation format and every vendor's key hierarchy.

## Mechanism

Split the work:

1. The user encrypts input to the enclave's public key.
2. The enclave decrypts, runs the logic, encrypts the output to the recipient, and produces an attestation: code measurement `H`, input ciphertext hash, output ciphertext hash.
3. A prover checks the attestation signature chain and the measurement inside a ZK circuit, and publishes one proof.
4. The contract verifies the proof against an approved measurement list. It never parses vendor attestation formats.

Because the check is a proof, the chain verifier is the same UltraHonk verifier as everywhere else, and the list of accepted enclave builds is a normal governance object.

## Trust model

State it exactly. The enclave sees plaintext, so confidentiality against the enclave operator depends on the hardware's isolation, which has a record of side-channel and key-extraction attacks. The proof does not remove that. What it adds is cheap, uniform on-chain verification and the ability to require several independent enclaves to agree: a contract can demand proofs of attestations from k of n vendors or builds, so a single break cannot forge a result.

## Fit with Opaque

Candidate uses are the places where logic is too heavy for a wallet-side circuit: a sealed-batch swap matcher and a private inference gateway. Both can run inside an enclave that never learns more than the batch it processes, with the pool's own proofs still guarding value movement. The pool itself keeps zero hardware trust.

## Open questions

- What is the cheapest circuit for verifying an attestation signature chain, and can it be aggregated with the settlement proof?
- Which measurement-whitelist governance keeps old, vulnerable builds from being accepted indefinitely?
