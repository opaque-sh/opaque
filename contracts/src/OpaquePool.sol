// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IOpaquePool} from "./interfaces/IOpaquePool.sol";
import {IHasher} from "./interfaces/IHasher.sol";
import {IVerifier} from "./interfaces/IVerifier.sol";
import {MerkleTree} from "./MerkleTree.sol";

/// @title OpaquePool
/// @notice Shielded pool for one token, $OPA. Notes are share-based and accrue donations, so shielded holders earn.
///         Every note still commits to an asset id (here always 1) so more assets could join a future pool version
///         without changing the circuit.
/// @dev No owner, no upgrade path, no way to move user funds. The guardian can only pause new shields.
///      Exits always work. Draft: unaudited, and the circuit it verifies against has no generated verifier yet.
///
///      Public inputs to the verifier, in order:
///        0 root, 1 nullifier0, 2 nullifier1, 3 commitment0, 4 commitment1, 5 assetId, 6 exitAmount, 7 extDataHash
///      The circuit proves: both inputs belong to `root`, nullifiers are correctly derived, every note carries
///      `assetId`, and in0 + in1 == out0 + out1 + exitAmount. `exitAmount` is in shares.
///
///      Fees: there is no shield fee. A flat unshield fee, set at deployment and paid in $OPA, stays in the pool
///      as backing, so it goes to everyone who is still shielded. Nothing is paid to a team address by the pool.
contract OpaquePool is IOpaquePool, MerkleTree {
    // ---------------------------------------------------------------- constants

    uint256 public constant ASSET_ID = 1;

    /// @dev Notes carry 120-bit amounts. Larger values are rejected so a note can never overflow the circuit.
    uint256 internal constant MAX_AMOUNT = (uint256(1) << 120) - 1;

    /// @dev ERC-4626 style virtual offset for the shares. Makes the donation inflation attack uneconomic.
    uint256 internal constant SHARE_OFFSET = 1e6;

    // ---------------------------------------------------------------- config (immutable)

    struct CapSchedule {
        uint128 initialCap; // backing cap at launch
        uint128 stepAmount; // cap added per step
        uint64 stepInterval; // seconds per step
        uint128 maxCap; // ceiling
    }

    IVerifier public immutable verifier;
    address public immutable token;
    address public immutable guardian;
    uint256 public immutable launchTime;
    /// @notice Flat unshield fee in token wei. Stays in the pool as backing for remaining holders.
    uint256 public immutable exitFee;

    CapSchedule public capSchedule;

    // ---------------------------------------------------------------- state

    mapping(uint256 => bool) public nullifierSpent;

    /// @notice Tokens backing all notes.
    uint256 public backing;
    /// @notice Total shares across all notes.
    uint256 public units;

    bool public depositsPaused;
    uint256 private _lock = 1;

    // ---------------------------------------------------------------- errors

    error Reentrancy();
    error DepositsPaused();
    error NotGuardian();
    error BadAmount();
    error NotInField();
    error CapExceeded();
    error ZeroShares();
    error UnknownRoot();
    error NullifierUsed();
    error DuplicateNullifier();
    error WrongCaller();
    error FeeTooHigh();
    error BadExit();
    error UnknownAsset();
    error ExitTargetsNotSupported();
    error InvalidProof();
    error TransferFailed();
    error EthNotAccepted();
    error FeeOnTransferToken();
    error InsufficientBacking();

    modifier nonReentrant() {
        if (_lock != 1) revert Reentrancy();
        _lock = 2;
        _;
        _lock = 1;
    }

    constructor(
        IHasher hasher_,
        IVerifier verifier_,
        address token_,
        address guardian_,
        uint256 exitFee_,
        CapSchedule memory cap
    ) MerkleTree(hasher_) {
        require(token_ != address(0), "zero address");
        require(cap.stepInterval != 0, "zero interval");
        require(cap.initialCap <= cap.maxCap, "cap order");

        verifier = verifier_;
        token = token_;
        guardian = guardian_;
        launchTime = block.timestamp;
        exitFee = exitFee_;
        capSchedule = cap;

        emit AssetRegistered(ASSET_ID, token_, true);
    }

    receive() external payable {
        revert EthNotAccepted();
    }

    // ---------------------------------------------------------------- views

    /// @notice Deposit cap on total backing right now. Rises on a fixed schedule, nobody can change it.
    function depositCap() public view returns (uint256) {
        CapSchedule memory s = capSchedule;
        uint256 steps = (block.timestamp - launchTime) / s.stepInterval;
        uint256 cap = uint256(s.initialCap) + steps * uint256(s.stepAmount);
        return cap > s.maxCap ? s.maxCap : cap;
    }

    /// @notice Shares minted for `amount` tokens at the current share price.
    function sharesForTokens(uint256 amount) public view returns (uint256) {
        return (amount * (units + SHARE_OFFSET)) / (backing + 1);
    }

    /// @notice Tokens redeemable for `shares` at the current share price.
    function tokensForShares(uint256 shares) public view returns (uint256) {
        return (shares * (backing + 1)) / (units + SHARE_OFFSET);
    }

    function isKnownRoot(uint256 root) public view override(IOpaquePool, MerkleTree) returns (bool) {
        return MerkleTree.isKnownRoot(root);
    }

    // ---------------------------------------------------------------- guardian

    /// @notice Pause or resume NEW shields. Exits and donations are never affected.
    function setDepositsPaused(bool paused) external {
        if (msg.sender != guardian) revert NotGuardian();
        depositsPaused = paused;
    }

    // ---------------------------------------------------------------- shield

    /// @inheritdoc IOpaquePool
    function shield(uint256 stub, uint256 amount, bytes calldata ciphertext)
        external
        nonReentrant
        returns (uint32 index)
    {
        if (depositsPaused) revert DepositsPaused();
        if (stub >= FIELD_SIZE) revert NotInField();
        if (amount == 0 || amount > MAX_AMOUNT) revert BadAmount();
        if (backing + amount > depositCap()) revert CapExceeded();

        uint256 minted = sharesForTokens(amount);
        if (minted == 0) revert ZeroShares();
        if (minted > MAX_AMOUNT) revert BadAmount();
        backing += amount;
        units += minted;
        _pull(amount);

        uint256 cm = hasher.hash4(1, stub, ASSET_ID, minted);
        index = _insertLeaf(cm);
        _recordRoot();

        emit NoteAdded(index, cm, ciphertext);
        emit Shielded(msg.sender, index, token, amount, minted);
    }

    // ---------------------------------------------------------------- donate

    /// @inheritdoc IOpaquePool
    /// @dev Donating raises the share price for every note.
    function donate(uint256 amount) external nonReentrant {
        if (amount == 0) revert BadAmount();
        backing += amount;
        _pull(amount);
        emit Donation(msg.sender, token, amount);
    }

    // ---------------------------------------------------------------- transact

    /// @inheritdoc IOpaquePool
    function transact(Transaction calldata t, bytes calldata proof) external nonReentrant {
        if (!isKnownRoot(t.root)) revert UnknownRoot();
        if (t.nullifiers[0] == t.nullifiers[1]) revert DuplicateNullifier();
        if (
            t.root >= FIELD_SIZE || t.nullifiers[0] >= FIELD_SIZE || t.nullifiers[1] >= FIELD_SIZE
                || t.commitments[0] >= FIELD_SIZE || t.commitments[1] >= FIELD_SIZE
        ) revert NotInField();
        if (t.assetId != ASSET_ID) revert UnknownAsset();
        if (t.exitAmount > MAX_AMOUNT) revert BadAmount();
        if (t.ext.data.length != 0) revert ExitTargetsNotSupported();
        if (t.ext.caller != address(0) && t.ext.caller != msg.sender) revert WrongCaller();

        uint256 tokens;
        uint256 relayerTokens;
        if (t.exitAmount == 0) {
            if (t.ext.fee != 0) revert BadExit();
        } else {
            if (t.ext.recipient == address(0)) revert BadExit();
            if (t.exitAmount > units) revert InsufficientBacking();
            if (t.ext.fee > t.exitAmount) revert FeeTooHigh();
            tokens = tokensForShares(t.exitAmount);
            relayerTokens = (tokens * t.ext.fee) / t.exitAmount;
            if (relayerTokens + exitFee > tokens) revert FeeTooHigh();
        }

        if (nullifierSpent[t.nullifiers[0]] || nullifierSpent[t.nullifiers[1]]) revert NullifierUsed();
        nullifierSpent[t.nullifiers[0]] = true;
        nullifierSpent[t.nullifiers[1]] = true;
        emit NullifierSpent(t.nullifiers[0]);
        emit NullifierSpent(t.nullifiers[1]);

        if (!verifier.verify(proof, publicInputs(t))) revert InvalidProof();

        uint32 i0 = _insertLeaf(t.commitments[0]);
        uint32 i1 = _insertLeaf(t.commitments[1]);
        _recordRoot();
        emit NoteAdded(i0, t.commitments[0], t.ext.ciphertext0);
        emit NoteAdded(i1, t.commitments[1], t.ext.ciphertext1);

        if (t.exitAmount != 0) _settleExit(t, tokens, relayerTokens);
    }

    /// @notice The public inputs the verifier sees for `t`. Exposed so clients and tests build the same array.
    function publicInputs(Transaction calldata t) public pure returns (bytes32[] memory p) {
        p = new bytes32[](8);
        p[0] = bytes32(t.root);
        p[1] = bytes32(t.nullifiers[0]);
        p[2] = bytes32(t.nullifiers[1]);
        p[3] = bytes32(t.commitments[0]);
        p[4] = bytes32(t.commitments[1]);
        p[5] = bytes32(t.assetId);
        p[6] = bytes32(t.exitAmount);
        p[7] = bytes32(extDataHash(t.ext));
    }

    /// @notice Binds recipient, relayer, fee and ciphertexts to the proof, so a relayer cannot change them.
    function extDataHash(ExtData calldata e) public pure returns (uint256) {
        return uint256(
            keccak256(
                abi.encode(
                    e.recipient, e.caller, e.fee, keccak256(e.data), keccak256(e.ciphertext0), keccak256(e.ciphertext1)
                )
            )
        ) % FIELD_SIZE;
    }

    /// @dev The flat fee tokens never leave: only `tokens - exitFee` is taken out of backing, while all
    ///      `exitAmount` shares are burned, which lifts the share price for everyone still shielded.
    function _settleExit(Transaction calldata t, uint256 tokens, uint256 relayerTokens) internal {
        uint256 payout = tokens - relayerTokens - exitFee;
        units -= t.exitAmount;
        backing -= tokens - exitFee;
        emit Exited(t.nullifiers[0], t.ext.recipient, token, payout);
        if (payout != 0) _push(t.ext.recipient, payout);
        if (relayerTokens != 0) _push(msg.sender, relayerTokens);
    }

    // ---------------------------------------------------------------- token plumbing

    function _pull(uint256 amount) internal {
        uint256 before = _balance();
        (bool ok, bytes memory ret) =
            token.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), amount));
        if (!ok || (ret.length != 0 && !abi.decode(ret, (bool)))) revert TransferFailed();
        if (_balance() - before != amount) revert FeeOnTransferToken();
    }

    function _push(address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        if (!ok || (ret.length != 0 && !abi.decode(ret, (bool)))) revert TransferFailed();
    }

    function _balance() internal view returns (uint256) {
        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSignature("balanceOf(address)", address(this)));
        if (!ok || ret.length < 32) revert TransferFailed();
        return abi.decode(ret, (uint256));
    }
}
