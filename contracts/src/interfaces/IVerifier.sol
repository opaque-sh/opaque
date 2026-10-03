// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IVerifier
/// @notice Shape of the generated UltraHonk verifier (Barretenberg `bb write_solidity_verifier`).
/// @dev The pool calls this with the public inputs in the fixed order documented in `OpaquePool.publicInputs`.
interface IVerifier {
    function verify(bytes calldata proof, bytes32[] calldata publicInputs) external view returns (bool);
}
