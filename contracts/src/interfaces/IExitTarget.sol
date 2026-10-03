// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IExitTarget (draft, multi-asset)
/// @notice Where a private exit made through the vault's ERC-4337 account goes: a swap router, a gateway, a
///         migration to another vault, or any contract the note owner names in the proof.
/// @dev Draft v2 of the v0 interface. The only change is the `asset` argument, so a single target can serve
///      several pool assets. The target may pull up to `amount` of `asset`, which the vault has just approved
///      (or sent, for the native asset, see the vault draft). Whatever it leaves, or everything if it reverts,
///      goes to `recipient` in the same asset.
interface IExitTarget {
    function onPrivateExit(address asset, uint256 amount, address recipient, bytes calldata data) external;
}
