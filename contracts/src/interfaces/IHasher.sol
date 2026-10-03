// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IHasher
/// @notice The hash used for the note tree and commitments. Production deployments point at a Poseidon2 (BN254)
///         implementation generated from the same constants as the circuit. Tests use a keccak stand-in.
/// @dev The pool never hashes anything else with this. Outputs must be field elements (below the BN254 scalar field).
interface IHasher {
    /// @notice Two-to-one hash for Merkle tree nodes.
    function hash2(uint256 a, uint256 b) external view returns (uint256);

    /// @notice Four-input hash for note commitments: cm = H(1, stub, assetId, amount).
    function hash4(uint256 a, uint256 b, uint256 c, uint256 d) external view returns (uint256);
}
