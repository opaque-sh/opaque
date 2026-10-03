// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IOpaquePool} from "./interfaces/IOpaquePool.sol";
import {IHasher} from "./interfaces/IHasher.sol";
import {IVerifier} from "./interfaces/IVerifier.sol";
import {MerkleTree} from "./MerkleTree.sol";

/// @title OpaquePool
/// @notice Shared multi-asset shielded pool. Two assets, fixed at deployment: native ETH (asset id 1, plain 1:1
///         notes) and the flagship token (asset id 2, share-based notes that accrue donations).
/// @dev No owner, no upgrade path, no way to move user funds. The guardian can only pause new shields.
///      Exits always work. Draft: unaudited, and the circuit it verifies against does not exist yet.
///
///      Public inputs to the verifier, in order:
///        0 root, 1 nullifier0, 2 nullifier1, 3 commitment0, 4 commitment1, 5 assetId, 6 exitAmount, 7 extDataHash
///      The circuit proves: both inputs belong to `root`, nullifiers are correctly derived, every note carries
///      `assetId`, and in0 + in1 == out0 + out1 + exitAmount. `exitAmount` is in the asset's note unit
///      (wei for ETH, shares for the flagship).
contract OpaquePool is IOpaquePool, MerkleTree {
    // ---------------------------------------------------------------- constants

    uint256 public constant ETH_ASSET_ID = 1;
    uint256 public constant FLAGSHIP_ASSET_ID = 2;

    /// @dev Notes carry 120-bit amounts. Larger values are rejected so a note can never overflow the circuit.
    uint256 internal constant MAX_AMOUNT = (uint256(1) << 120) - 1;

    /// @dev ERC-4626 style virtual offset for the flagship shares. Makes the donation inflation attack uneconomic.
    uint256 internal constant SHARE_OFFSET = 1e6;

    uint256 public constant MAX_SHIELD_FEE_BPS = 100;
    uint256 internal constant BPS = 10_000;

    // ---------------------------------------------------------------- config (immutable)

    struct CapSchedule {
        uint128 initialCap; // backing cap at launch
        uint128 stepAmount; // cap added per step
        uint64 stepInterval; // seconds per step
        uint128 maxCap; // ceiling
    }

    IVerifier public immutable verifier;
    address public immutable flagship;
    address public immutable guardian;
    address public immutable feeSink;
    uint256 public immutable launchTime;
    uint256 public immutable ethShieldFeeBps;
    uint256 public immutable ethExitFee;

    CapSchedule public ethCapSchedule;
    CapSchedule public flagshipCapSchedule;

    // ---------------------------------------------------------------- state

    mapping(uint256 => bool) public nullifierSpent;

    /// @notice Sum of unspent ETH note value, in wei.
    uint256 public ethNotes;
    /// @notice ETH collected as fees, waiting for `collectEthFees`.
    uint256 public ethFeesAccrued;
    /// @notice Flagship tokens backing all flagship notes.
    uint256 public flagshipBacking;
    /// @notice Total flagship shares across all notes.
    uint256 public flagshipUnits;

    bool public depositsPaused;
    uint256 private _lock = 1;

    // ---------------------------------------------------------------- errors

    error Reentrancy();
    error DepositsPaused();
    error NotGuardian();
    error UnknownAsset();
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
        address flagship_,
        address guardian_,
        address feeSink_,
        uint256 ethShieldFeeBps_,
        uint256 ethExitFee_,
        CapSchedule memory ethCap,
        CapSchedule memory flagshipCap
    ) MerkleTree(hasher_) {
        require(flagship_ != address(0) && feeSink_ != address(0), "zero address");
        require(ethShieldFeeBps_ <= MAX_SHIELD_FEE_BPS, "shield fee too high");
        require(ethCap.stepInterval != 0 && flagshipCap.stepInterval != 0, "zero interval");
        require(ethCap.initialCap <= ethCap.maxCap && flagshipCap.initialCap <= flagshipCap.maxCap, "cap order");

        verifier = verifier_;
        flagship = flagship_;
        guardian = guardian_;
        feeSink = feeSink_;
        launchTime = block.timestamp;
        ethShieldFeeBps = ethShieldFeeBps_;
        ethExitFee = ethExitFee_;
        ethCapSchedule = ethCap;
        flagshipCapSchedule = flagshipCap;

        emit AssetRegistered(ETH_ASSET_ID, address(0), false);
        emit AssetRegistered(FLAGSHIP_ASSET_ID, flagship_, true);
    }

    receive() external payable {
        revert EthNotAccepted();
    }

    // ---------------------------------------------------------------- views

    function assetIdOf(address asset) public view returns (uint256) {
        if (asset == address(0)) return ETH_ASSET_ID;
        if (asset == flagship) return FLAGSHIP_ASSET_ID;
        return 0;
    }

    function isKnownRoot(uint256 root) public view override(IOpaquePool, MerkleTree) returns (bool) {
        return MerkleTree.isKnownRoot(root);
    }

    /// @notice Deposit cap for `asset` right now. Rises on a fixed schedule, nobody can change it.
    function depositCap(address asset) public view returns (uint256) {
        CapSchedule memory s = asset == address(0) ? ethCapSchedule : flagshipCapSchedule;
        uint256 steps = (block.timestamp - launchTime) / s.stepInterval;
        uint256 cap = uint256(s.initialCap) + steps * uint256(s.stepAmount);
        return cap > s.maxCap ? s.maxCap : cap;
    }

    /// @notice Shares minted for `amount` flagship tokens at the current share price.
    function sharesForTokens(uint256 amount) public view returns (uint256) {
        return (amount * (flagshipUnits + SHARE_OFFSET)) / (flagshipBacking + 1);
    }

    /// @notice Flagship tokens redeemable for `shares` at the current share price.
    function tokensForShares(uint256 shares) public view returns (uint256) {
        return (shares * (flagshipBacking + 1)) / (flagshipUnits + SHARE_OFFSET);
    }

    // ---------------------------------------------------------------- guardian

    /// @notice Pause or resume NEW shields. Exits and donations are never affected.
    function setDepositsPaused(bool paused) external {
        if (msg.sender != guardian) revert NotGuardian();
        depositsPaused = paused;
    }

    // ---------------------------------------------------------------- shield

    /// @inheritdoc IOpaquePool
    function shield(address asset, uint256 stub, uint256 amount, bytes calldata ciphertext)
        external
        payable
        nonReentrant
        returns (uint32 index)
    {
        if (depositsPaused) revert DepositsPaused();
        if (stub >= FIELD_SIZE) revert NotInField();
        if (amount == 0 || amount > MAX_AMOUNT) revert BadAmount();

        uint256 assetId = assetIdOf(asset);
        uint256 units;

        if (assetId == ETH_ASSET_ID) {
            if (msg.value != amount) revert BadAmount();
            uint256 fee = (amount * ethShieldFeeBps) / BPS;
            units = amount - fee;
            if (units == 0) revert BadAmount();
            if (ethNotes + units + ethFeesAccrued + fee > depositCap(address(0))) revert CapExceeded();
            ethNotes += units;
            ethFeesAccrued += fee;
        } else if (assetId == FLAGSHIP_ASSET_ID) {
            if (msg.value != 0) revert BadAmount();
            if (flagshipBacking + amount > depositCap(flagship)) revert CapExceeded();
            units = sharesForTokens(amount);
            if (units == 0) revert ZeroShares();
            if (units > MAX_AMOUNT) revert BadAmount();
            flagshipBacking += amount;
            flagshipUnits += units;
            _pull(amount);
        } else {
            revert UnknownAsset();
        }

        uint256 cm = hasher.hash4(1, stub, assetId, units);
        index = _insertLeaf(cm);
        _recordRoot();

        emit NoteAdded(index, cm, ciphertext);
        emit Shielded(msg.sender, index, asset, amount, units);
    }

    // ---------------------------------------------------------------- donate

    /// @inheritdoc IOpaquePool
    /// @dev Only the flagship is share-based. Donating raises the share price for every flagship note.
    function donate(address asset, uint256 amount) external payable nonReentrant {
        if (asset != flagship) revert UnknownAsset();
        if (msg.value != 0) revert BadAmount();
        if (amount == 0) revert BadAmount();
        flagshipBacking += amount;
        _pull(amount);
        emit Donation(msg.sender, asset, amount);
    }

    /// @notice Send accrued ETH fees to the fee sink (the buyback keeper). Permissionless, destination is fixed.
    function collectEthFees() external nonReentrant returns (uint256 amount) {
        amount = ethFeesAccrued;
        if (amount == 0) return 0;
        ethFeesAccrued = 0;
        _sendEth(feeSink, amount);
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
        if (t.assetId != ETH_ASSET_ID && t.assetId != FLAGSHIP_ASSET_ID) revert UnknownAsset();
        if (t.exitAmount > MAX_AMOUNT) revert BadAmount();
        if (t.ext.data.length != 0) revert ExitTargetsNotSupported();
        if (t.ext.caller != address(0) && t.ext.caller != msg.sender) revert WrongCaller();

        // Fee and recipient checks that do not depend on the proof.
        uint256 protocolFee;
        if (t.exitAmount == 0) {
            if (t.ext.fee != 0) revert BadExit();
        } else {
            if (t.ext.recipient == address(0)) revert BadExit();
            if (t.assetId == ETH_ASSET_ID) protocolFee = ethExitFee;
            if (t.ext.fee + protocolFee > t.exitAmount) revert FeeTooHigh();
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

        if (t.exitAmount != 0) _settleExit(t, protocolFee);
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

    function _settleExit(Transaction calldata t, uint256 protocolFee) internal {
        if (t.assetId == ETH_ASSET_ID) {
            if (t.exitAmount > ethNotes) revert InsufficientBacking();
            ethNotes -= t.exitAmount;
            ethFeesAccrued += protocolFee;
            uint256 payout = t.exitAmount - t.ext.fee - protocolFee;
            emit Exited(t.nullifiers[0], t.ext.recipient, address(0), payout);
            if (payout != 0) _sendEth(t.ext.recipient, payout);
            if (t.ext.fee != 0) _sendEth(msg.sender, t.ext.fee);
        } else {
            if (t.exitAmount > flagshipUnits) revert InsufficientBacking();
            uint256 tokens = tokensForShares(t.exitAmount);
            uint256 feeTokens = (tokens * t.ext.fee) / t.exitAmount;
            uint256 payout = tokens - feeTokens;
            flagshipUnits -= t.exitAmount;
            flagshipBacking -= tokens;
            emit Exited(t.nullifiers[0], t.ext.recipient, flagship, payout);
            if (payout != 0) _push(t.ext.recipient, payout);
            if (feeTokens != 0) _push(msg.sender, feeTokens);
        }
    }

    // ---------------------------------------------------------------- token and ETH plumbing

    function _sendEth(address to, uint256 amount) internal {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    function _pull(uint256 amount) internal {
        uint256 before = _balance();
        (bool ok, bytes memory ret) =
            flagship.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), amount));
        if (!ok || (ret.length != 0 && !abi.decode(ret, (bool)))) revert TransferFailed();
        if (_balance() - before != amount) revert FeeOnTransferToken();
    }

    function _push(address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = flagship.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        if (!ok || (ret.length != 0 && !abi.decode(ret, (bool)))) revert TransferFailed();
    }

    function _balance() internal view returns (uint256) {
        (bool ok, bytes memory ret) = flagship.staticcall(abi.encodeWithSignature("balanceOf(address)", address(this)));
        if (!ok || ret.length < 32) revert TransferFailed();
        return abi.decode(ret, (uint256));
    }
}
