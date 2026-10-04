// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IOpaquePool (draft)
/// @notice Draft external surface of the $OPA shielded pool. Nothing here is final. It exists so the
///         circuit, the client and the contracts can be designed against one shared shape.
/// @dev Key differences from the v0 PrivateVault:
///      - Every note commits to an asset id: cm = H(1, stub, assetId, amount). Here the only asset is $OPA (id 1),
///        but the field stays so a future pool version can add assets without a new circuit.
///      - Notes are share-based and accrue donations.
interface IOpaquePool {
    struct ExtData {
        address recipient;
        address caller;
        uint256 fee;
        bytes data;
        bytes ciphertext0;
        bytes ciphertext1;
    }

    struct Transaction {
        uint256 root;
        uint256[2] nullifiers;
        uint256[2] commitments;
        uint256 assetId;
        uint256 exitAmount;
        ExtData ext;
    }

    event NoteAdded(uint256 indexed index, uint256 commitment, bytes ciphertext);
    event NullifierSpent(uint256 indexed nullifier);
    event Shielded(address indexed from, uint256 indexed index, address indexed asset, uint256 amount, uint256 units);
    event Exited(uint256 indexed nullifier, address indexed recipient, address indexed asset, uint256 amount);
    event Donation(address indexed from, address indexed asset, uint256 amount);
    event AssetRegistered(uint256 indexed assetId, address indexed asset, bool shareBased);

    /// @notice Pull `amount` $OPA into a note completed with `stub`.
    function shield(uint256 stub, uint256 amount, bytes calldata ciphertext) external returns (uint32 index);

    /// @notice Spend up to two notes, create two notes, optionally exit part of the value.
    function transact(Transaction calldata t, bytes calldata proof) external;

    /// @notice Add $OPA to the backing without minting shares. Raises the share price for every note.
    function donate(uint256 amount) external;

    function isKnownRoot(uint256 root) external view returns (bool);
    function nullifierSpent(uint256 nullifier) external view returns (bool);
}
