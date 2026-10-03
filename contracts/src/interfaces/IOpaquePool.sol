// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IOpaquePool (draft)
/// @notice Draft external surface of the multi-asset shielded pool. Nothing here is final. It exists so the
///         circuit, the client and the contracts can be designed against one shared shape.
/// @dev Key differences from the v0 PrivateVault:
///      - Every note commits to an asset id: cm = H(1, stub, assetId, amount).
///      - A transaction spends and creates notes of ONE asset. Cross-asset moves go through exits and shields
///        (or, later, an in-circuit epoch swap, see docs/DESIGN.md).
///      - ETH notes are plain 1:1 amounts. The flagship asset is share-based and accrues donations.
///      - `address(0)` is the native asset (ETH).
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

    /// @notice Pull `amount` of `asset` (or msg.value for the native asset) into a note completed with `stub`.
    function shield(address asset, uint256 stub, uint256 amount, bytes calldata ciphertext)
        external
        payable
        returns (uint32 index);

    /// @notice Spend up to two notes of one asset, create two notes, optionally exit part of the value.
    function transact(Transaction calldata t, bytes calldata proof) external;

    /// @notice Add value to the backing of a share-based asset without minting shares.
    function donate(address asset, uint256 amount) external payable;

    function assetIdOf(address asset) external view returns (uint256);
    function isKnownRoot(uint256 root) external view returns (bool);
    function nullifierSpent(uint256 nullifier) external view returns (bool);
}
