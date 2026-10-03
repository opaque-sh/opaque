// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {IPoseidon2} from "poseidon2-evm/IPoseidon2.sol";

import {PoseidonMerkleTree} from "./PoseidonMerkleTree.sol";
import {NoteHash} from "./libraries/NoteHash.sol";
import {IVerifier} from "./interfaces/IVerifier.sol";
import {IAccount, IEntryPoint, PackedUserOperation} from "./interfaces/IERC4337.sol";
import {IPonsCurve, IPonsFactory} from "./interfaces/IPons.sol";
import {PonsMarket} from "./PonsSwapper.sol";

/// @notice Where a private exit made through the ERC-4337 account goes: a sale router, a migration to another vault,
///         or any contract the note owner names in the proof. It may pull up to `amount` ZERO it was just approved for;
///         whatever it leaves, or everything if it reverts, goes to `recipient` as ZERO.
interface IExitTarget {
    function onPrivateExit(uint256 amount, address recipient, bytes calldata data) external;
}

/// @title PrivateVault
/// @notice The private side of ZERO, an ordinary ERC-20 launched on Pons. Shielding moves ZERO into this vault and
///         creates an encrypted note; unshielding moves it back out. Inside, notes are spent with a zero-knowledge
///         proof and a signature by the owner's wallet, so amounts, senders and recipients stay private.
/// @dev Notes hold vault shares. ZERO backing all notes is `totalBacking` (B); shares are `totalShares` (S). A
///      donation adds to B and raises the value of every share: the fee harvester donates the Pons creator fees.
///      The vault is also an ERC-4337 account: a UserOperation carries a transaction and its proof, and the whole
///      state transition happens in `validateUserOp`, so execution can never fail and leave the gas deposit paying
///      for nothing. The EntryPoint deposit pays the bundler; the fee harvester keeps it topped up with ETH from the
///      Pons creator fees. Each operation pays a flat network fee in shares (`ext.gasFee`), donated to every note:
///      it is set in ZERO once an hour from the price average, so an operation never fails because the price moved
///      between signing and inclusion.
///      Every address the vault works with is fixed at construction: there is no owner and no initializer. The one
///      role is the guardian, who can only stop new ZERO from entering (`shield`, and so private buys); spending,
///      transfers, sales and exits always work, so nobody can be locked in.
contract PrivateVault is PoseidonMerkleTree, EIP712, IAccount {
    using SafeERC20 for IERC20;

    // ------------------------------------------------------------------
    // Types
    // ------------------------------------------------------------------

    struct Keys {
        uint256 opk; // owner public key, H(nk, wallet key): see circuits/crates/note
        bytes32 viewKey; // X25519 public key for note encryption
    }

    /// @dev Bound to the proof through extDataHash, so nobody can change it after the prover signs off.
    struct ExtData {
        address recipient; // receives exitShares converted to ZERO
        address caller; // if non-zero, only this address may submit (the router; this contract for ERC-4337)
        uint256 gasFee; // shares, out of exitShares, donated to every note as the network fee
        bytes data; // parameters for `caller`: router sale terms, or the ERC-4337 fields (see validateUserOp)
        bytes ciphertext0;
        bytes ciphertext1;
    }

    /// @dev An exit applied in validation and settled in execution by the target the proof names (a sale, a
    ///      migration...): `amount` ZERO in escrow, `recipient` gets whatever the target does not take.
    struct Sale {
        uint256 amount;
        address target;
        address recipient;
        bytes data;
    }

    struct Transaction {
        uint256 root;
        uint256[2] nullifiers;
        uint256[2] commitments;
        uint256 exitShares;
        ExtData ext;
    }

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------

    event KeysRegistered(address indexed owner, uint256 opk, bytes32 viewKey);
    event NoteAdded(uint256 indexed index, uint256 commitment, bytes ciphertext);
    /// @notice `index` is the leaf of the note created: wallets read the note's shares from here, because they are
    ///         only known on-chain and the note's ciphertext is written before the transaction runs.
    event Shielded(address indexed from, uint256 indexed index, uint256 amount, uint256 shares);
    /// @notice `nullifier` is the transaction's first nullifier, so a wallet can tell which of its spends this was.
    event Exited(uint256 indexed nullifier, address indexed recipient, uint256 amount, uint256 shares);
    event NullifierSpent(uint256 indexed nullifier);
    /// @notice `from` is the vault itself for an operation's network fee, zero for ZERO absorbed from plain transfers.
    event Donation(address indexed from, uint256 amount);
    event PriceUpdated(uint256 tokensPerEthEma);
    event NetworkFeeUpdated(uint256 networkFee);
    /// @notice `saleId` is the sale's first nullifier.
    event SaleSettled(uint256 indexed saleId, bool swapped);
    /// @notice Vault totals after every change: the share value B/S over time can be rebuilt from these alone.
    event VaultUpdated(uint256 totalBacking, uint256 totalShares);
    event EntriesPaused(bool paused);
    event GuardianTransferred(address indexed previousGuardian, address indexed newGuardian);

    // ------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------

    error ZeroAddress();
    error NotAFieldElement();
    error ZeroShares();
    error UnknownRoot();
    error NullifierAlreadySpent();
    error DuplicateNullifier();
    error InvalidProof();
    error InvalidSignature();
    error SignatureExpired();
    error WrongCaller();
    error FeeExceedsExit();
    error NotEntryPoint();
    error InvalidUserOp();
    error InsufficientGasFee();
    error GasCostAboveLimit();
    error EntriesArePaused();
    error NotGuardian();
    error NoPrice();
    error NoSuchSale();

    // ------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------

    bytes32 private constant REGISTER_TYPEHASH =
        keccak256("Register(address owner,uint256 opk,bytes32 viewKey,uint256 nonce,uint256 deadline)");

    /// @dev Virtual shares against the first-depositor inflation attack (as in OpenZeppelin ERC-4626).
    uint256 public constant VIRTUAL_SHARES = 1e6;

    /// @notice How often the network fee in ZERO follows the price average. The previous fee stays accepted until the
    ///         next update, so an operation signed just before an update still goes through.
    uint256 public constant NETWORK_FEE_INTERVAL = 1 hours;
    uint256 private constant SIG_VALIDATION_FAILED = 1;
    uint256 private constant BPS_DENOMINATOR = 10_000;

    /// @dev A block's closing price enters the average clamped to this distance from it, so each block moves the
    ///      average by at most 1/8 of 10% = 1.25%, however far the price was pushed.
    uint256 public constant MAX_PRICE_STEP_BPS = 1_000;

    /// @notice ZERO, the Pons token this vault holds.
    IERC20 public immutable zero;
    IPonsFactory public immutable ponsFactory;
    IPonsCurve public immutable curve;
    IPoolManager public immutable poolManager;
    /// @notice The Pons Uniswap v4 pool ZERO trades on after graduation.
    PoolId public immutable poolId;
    IVerifier public immutable verifier;
    IEntryPoint public immutable entryPoint;
    /// @notice The most an operation may charge the deposit (its maximum gas cost), and the value in ETH of the network
    ///         fee every operation pays. Equal on purpose: an operation can never take more ETH from the deposit than
    ///         it pays in ZERO, so filling bundles with one's own operations to drain it does not pay.
    uint256 public immutable maxOpCostWei;

    /// @notice May pause and resume new entries (`shield`), and hand the role on. Zero once renounced.
    address public guardian;
    /// @notice While true, `shield` reverts. Nothing else is affected.
    bool public entriesPaused;

    /// @notice Sales validated but not yet settled, by first nullifier.
    mapping(uint256 => Sale) public pendingSales;
    /// @notice ZERO held for pending sales: in the vault, but no longer backing any note.
    uint256 public pendingSaleTotal;
    /// @notice Exponential moving average of the price, in ZERO per ETH scaled by 1e18.
    uint256 public tokensPerEthEma;
    /// @notice The network fee, in ZERO, and the one it replaced: an operation must pay at least the lower of the two.
    uint128 public networkFee;
    uint128 public previousNetworkFee;
    uint64 public networkFeeSetAt;
    /// @notice Price at the latest update, in the same unit as the average. It enters the average when a later block
    ///         is first poked, so a block counts with the price at its last poke.
    uint192 public lastSpot;
    /// @notice Block of the latest update (on Robinhood Chain, `block.number` follows the L1 block).
    uint64 public lastPriceBlock;

    uint256 public totalBacking;
    uint256 public totalShares;
    mapping(uint256 => bool) public nullifierSpent;

    mapping(address => Keys) public keysOf;
    mapping(address => uint256) public registerNonces;

    constructor(
        string memory name_,
        IERC20 zero_,
        IPonsFactory ponsFactory_,
        IPonsCurve curve_,
        IPoolManager poolManager_,
        PoolId poolId_,
        IVerifier verifier_,
        IPoseidon2 hasher_,
        IEntryPoint entryPoint_,
        uint256 maxOpCostWei_,
        address guardian_
    ) PoseidonMerkleTree(hasher_) EIP712(name_, "1") {
        if (address(zero_) == address(0) || address(verifier_) == address(0)) revert ZeroAddress();
        zero = zero_;
        ponsFactory = ponsFactory_;
        curve = curve_;
        poolManager = poolManager_;
        poolId = poolId_;
        verifier = verifier_;
        entryPoint = entryPoint_;
        maxOpCostWei = maxOpCostWei_;
        guardian = guardian_;
        emit GuardianTransferred(address(0), guardian_);
    }

    // ------------------------------------------------------------------
    // Key registry
    // ------------------------------------------------------------------

    function register(uint256 opk, bytes32 viewKey) external {
        _register(msg.sender, opk, viewKey);
    }

    /// @notice Registers keys for `owner` with an EIP-712 signature (EOA or ERC-1271), submitted by anyone.
    function registerFor(address owner, uint256 opk, bytes32 viewKey, uint256 deadline, bytes calldata signature)
        external
    {
        if (block.timestamp > deadline) revert SignatureExpired();
        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(REGISTER_TYPEHASH, owner, opk, viewKey, registerNonces[owner]++, deadline))
        );
        if (!SignatureChecker.isValidSignatureNow(owner, digest, signature)) revert InvalidSignature();
        _register(owner, opk, viewKey);
    }

    // ------------------------------------------------------------------
    // Guardian
    // ------------------------------------------------------------------

    /// @notice Stops (or resumes) new ZERO entering notes. It cannot touch anything already inside.
    function setEntriesPaused(bool paused) external {
        if (msg.sender != guardian) revert NotGuardian();
        entriesPaused = paused;
        emit EntriesPaused(paused);
    }

    /// @notice Hands the guardian role on; `address(0)` renounces it, and entries can then never be paused again.
    function transferGuardian(address newGuardian) external {
        if (msg.sender != guardian) revert NotGuardian();
        emit GuardianTransferred(guardian, newGuardian);
        guardian = newGuardian;
    }

    // ------------------------------------------------------------------
    // Private side
    // ------------------------------------------------------------------

    /// @notice Moves `amount` ZERO from the caller into a note completed with `stub`. The caller must have approved
    ///         the vault.
    /// @param stub H(opk, rho, r), chosen by the note owner so nobody else can recognise the note.
    /// @param ciphertext Encrypted note data for the owner's wallet to recover it.
    function shield(uint256 stub, uint256 amount, bytes calldata ciphertext) external returns (uint32 index) {
        if (entriesPaused) revert EntriesArePaused();
        if (stub >= NoteHash.FIELD) revert NotAFieldElement();
        zero.safeTransferFrom(msg.sender, address(this), amount);

        uint256 shares = _mintShares(amount);
        uint256 cm = NoteHash.commitment(hasher, stub, shares);
        index = _insertPair(cm, 0);

        emit Shielded(msg.sender, index, amount, shares);
        emit NoteAdded(index, cm, ciphertext);
    }

    /// @notice Adds `amount` ZERO from the caller to the tokens backing every note, without minting shares.
    function donate(uint256 amount) external {
        zero.safeTransferFrom(msg.sender, address(this), amount);
        totalBacking += amount;
        emit Donation(msg.sender, amount);
        emit VaultUpdated(totalBacking, totalShares);
    }

    /// @notice Adds ZERO that reached the vault by a plain transfer to the tokens backing every note. Permissionless;
    ///         the harvester calls it on every harvest.
    function absorb() external returns (uint256 amount) {
        uint256 held = totalBacking + pendingSaleTotal;
        uint256 balance = zero.balanceOf(address(this));
        if (balance <= held) return 0;
        amount = balance - held;
        totalBacking += amount;
        emit Donation(address(0), amount);
        emit VaultUpdated(totalBacking, totalShares);
    }

    /// @notice Spends up to two notes, creates two notes and optionally exits shares as ZERO to a recipient.
    function transact(Transaction calldata t, bytes calldata proof) external {
        if (t.ext.caller != address(0) && msg.sender != t.ext.caller) revert WrongCaller();
        _transact(t, proof, false, false);
    }

    // ------------------------------------------------------------------
    // ERC-4337
    // ------------------------------------------------------------------

    /// @notice Validates and applies a private transaction carried in `userOp.signature` as
    ///         `abi.encode(Transaction, proof)`. The proof names this contract as `ext.caller`, and `ext.data` is
    ///         `abi.encode(minCallGasLimit, exitTarget, recipient, exitData)`. With an `exitTarget`, the exit is held
    ///         in escrow and handed to that contract in execution (see IExitTarget); without one, it goes to
    ///         `ext.recipient` at once, as in `transact`.
    /// @dev The proof does not fix the other gas fields, so bundlers can estimate and price the operation. That is
    ///      safe: a bundler could only hurt the user by starving execution, which `minCallGasLimit` prevents, and
    ///      the deposit is protected because an operation's maximum cost may not exceed `maxOpCostWei`, which is also
    ///      what its network fee is worth. Validation reads only this contract's storage: no price is read here.
    ///      An invalid proof returns SIG_VALIDATION_FAILED instead of reverting, as ERC-4337 expects of a bad
    ///      signature: wallets can then estimate gas with a placeholder proof and prove (and sign) only once.
    ///      Nothing is written in that case, and the EntryPoint refuses to execute the operation.
    function validateUserOp(PackedUserOperation calldata op, bytes32, uint256 missingAccountFunds)
        external
        returns (uint256)
    {
        if (msg.sender != address(entryPoint)) revert NotEntryPoint();
        (Transaction memory t, bytes memory proof) = abi.decode(op.signature, (Transaction, bytes));

        if (t.ext.caller != address(this)) revert WrongCaller();
        if (op.initCode.length != 0 || op.paymasterAndData.length != 0) revert InvalidUserOp();
        if (keccak256(op.callData) != keccak256(abi.encodeCall(this.execute4337, (t.nullifiers[0])))) {
            revert InvalidUserOp();
        }
        // One nonce key per first nullifier: operations from different users never queue behind each other.
        if (op.nonce != uint256(uint192(t.nullifiers[0])) << 64) revert InvalidUserOp();
        (uint256 minCallGasLimit, address exitTarget, address recipient, bytes memory exitData) =
            abi.decode(t.ext.data, (uint256, address, address, bytes));
        uint256 callGasLimit = uint128(uint256(op.accountGasLimits));
        if (callGasLimit < minCallGasLimit) revert InvalidUserOp();

        uint256 maxCost = (uint256(op.accountGasLimits >> 128) + callGasLimit + op.preVerificationGas)
            * uint128(uint256(op.gasFees));
        if (maxCost > maxOpCostWei) revert GasCostAboveLimit();
        uint256 minFee = networkFee < previousNetworkFee ? networkFee : previousNetworkFee;
        if (minFee == 0) revert NoPrice();
        if (convertToAssets(t.ext.gasFee) < minFee) revert InsufficientGasFee();

        // An exit to a target: it waits in escrow and the target runs in execution, where a failure cannot undo
        // the private state change already made here.
        bool toTarget = exitTarget != address(0);
        if (toTarget && recipient == address(0)) revert ZeroAddress();
        (bool valid, uint256 amount) = _transact(t, proof, toTarget, true);
        if (!valid) return SIG_VALIDATION_FAILED;
        if (toTarget) {
            if (amount == 0) revert InvalidUserOp();
            pendingSales[t.nullifiers[0]] = Sale(amount, exitTarget, recipient, exitData);
            pendingSaleTotal += amount;
        }

        if (missingAccountFunds != 0) {
            // Normally zero: the deposit pays. If the deposit is short this fails and the bundler drops the op.
            (bool ok,) = payable(msg.sender).call{value: missingAccountFunds}("");
            (ok);
        }
        return 0;
    }

    /// @notice Execution step of a UserOperation: hands its exit, if any, to the target. Never reverts on a failed
    ///         target: the ZERO then goes to the recipient.
    /// @dev The target pulls the ZERO itself, so a revert takes the pull back with it. It is approved for exactly the
    ///      exit's amount, the approval is cleared afterwards, and what it left (read from the remaining allowance, so
    ///      nothing it sends to the vault meanwhile is counted) goes to the recipient.
    function execute4337(uint256 saleId) external {
        if (msg.sender != address(entryPoint)) revert NotEntryPoint();
        Sale memory sale = pendingSales[saleId];
        if (sale.amount == 0) return;
        delete pendingSales[saleId];
        pendingSaleTotal -= sale.amount;

        zero.forceApprove(sale.target, sale.amount);
        bool settled;
        try IExitTarget(sale.target).onPrivateExit(sale.amount, sale.recipient, sale.data) {
            settled = true;
        } catch {}
        uint256 left = zero.allowance(address(this), sale.target);
        zero.forceApprove(sale.target, 0);
        if (!settled) left = sale.amount;
        if (left != 0) zero.safeTransfer(sale.recipient, left);
        emit SaleSettled(saleId, settled);
    }

    /// @notice If an exit's execution ran out of gas, anyone can release its ZERO to the recipient.
    function claimSale(uint256 saleId) external {
        Sale memory sale = pendingSales[saleId];
        if (sale.amount == 0) revert NoSuchSale();
        delete pendingSales[saleId];
        pendingSaleTotal -= sale.amount;
        zero.safeTransfer(sale.recipient, sale.amount);
        emit SaleSettled(saleId, false);
    }

    /// @notice Anyone can add stake for this account in the EntryPoint. Nobody can ever unlock it.
    function addStake(uint32 unstakeDelaySec) external payable {
        entryPoint.addStake{value: msg.value}(unstakeDelaySec);
    }

    // ------------------------------------------------------------------
    // Price average and network fee
    // ------------------------------------------------------------------

    /// @notice Folds the market price into the average. Permissionless; the router and the harvester call it on
    ///         every trade.
    /// @dev The first update of a block folds the previous update's price, clamped, into the average; every update
    ///      records the current price as the new one. ERC-4337 validation reads only the stored average.
    function poke() public {
        uint256 spot = PonsMarket.spot(ponsFactory, address(zero), curve, poolManager, poolId);
        if (spot == 0) return;

        uint256 ema = tokensPerEthEma;
        if (ema == 0) {
            ema = spot;
            tokensPerEthEma = ema;
            emit PriceUpdated(ema);
        } else if (block.number != lastPriceBlock) {
            uint256 close = lastSpot;
            uint256 hi = ema * (BPS_DENOMINATOR + MAX_PRICE_STEP_BPS) / BPS_DENOMINATOR;
            uint256 lo = ema * (BPS_DENOMINATOR - MAX_PRICE_STEP_BPS) / BPS_DENOMINATOR;
            if (close > hi) close = hi;
            else if (close < lo) close = lo;
            ema = (ema * 7 + close) / 8;
            tokensPerEthEma = ema;
            emit PriceUpdated(ema);
        }
        lastSpot = uint192(spot);
        lastPriceBlock = uint64(block.number);

        if (networkFee == 0 || block.timestamp >= networkFeeSetAt + NETWORK_FEE_INTERVAL) _setNetworkFee(ema);
    }

    /// @dev The fee follows the average, so it keeps its value in ETH; the one it replaces stays accepted for an hour.
    function _setNetworkFee(uint256 ema) private {
        uint256 fee = FullMath.mulDiv(maxOpCostWei, ema, 1e18);
        if (fee == 0) fee = 1;
        if (fee > type(uint128).max) fee = type(uint128).max;
        previousNetworkFee = networkFee == 0 ? uint128(fee) : networkFee;
        networkFee = uint128(fee);
        networkFeeSetAt = uint64(block.timestamp);
        emit NetworkFeeUpdated(fee);
    }

    /// @notice Public inputs in the exact order the circuit declares them.
    function publicInputs(Transaction calldata t) external view returns (bytes32[] memory) {
        return _publicInputs(t);
    }

    function extDataHash(ExtData memory ext) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(ext))) % NoteHash.FIELD;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        return assets * (totalShares + VIRTUAL_SHARES) / (totalBacking + 1);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return shares * (totalBacking + 1) / (totalShares + VIRTUAL_SHARES);
    }

    // ------------------------------------------------------------------
    // Internal
    // ------------------------------------------------------------------

    /// @param softProof Report an invalid proof as `valid = false` (ERC-4337 validation) instead of reverting.
    /// @return valid False only when `softProof` and the proof is invalid; nothing was written then.
    /// @return amount ZERO exited to the recipient (or kept in escrow when `toEscrow`).
    function _transact(Transaction memory t, bytes memory proof, bool toEscrow, bool softProof)
        internal
        returns (bool valid, uint256 amount)
    {
        if (!isKnownRoot(t.root)) revert UnknownRoot();
        if (t.nullifiers[0] == t.nullifiers[1]) revert DuplicateNullifier();
        for (uint256 i; i < 2; ++i) {
            if (nullifierSpent[t.nullifiers[i]]) revert NullifierAlreadySpent();
            if (t.commitments[i] >= NoteHash.FIELD || t.nullifiers[i] >= NoteHash.FIELD) revert NotAFieldElement();
        }
        if (t.exitShares >= NoteHash.FIELD) revert NotAFieldElement();
        if (t.ext.gasFee > t.exitShares) revert FeeExceedsExit();
        uint256 userShares = t.exitShares - t.ext.gasFee;
        if (userShares != 0 && !toEscrow && t.ext.recipient == address(0)) revert ZeroAddress();

        if (softProof) {
            try verifier.verify(proof, _publicInputs(t)) returns (bool ok) {
                if (!ok) return (false, 0);
            } catch {
                return (false, 0);
            }
        } else if (!verifier.verify(proof, _publicInputs(t))) {
            revert InvalidProof();
        }
        valid = true;

        for (uint256 i; i < 2; ++i) {
            nullifierSpent[t.nullifiers[i]] = true;
            emit NullifierSpent(t.nullifiers[i]);
        }
        uint32 first = _insertPair(t.commitments[0], t.commitments[1]);
        emit NoteAdded(first, t.commitments[0], t.ext.ciphertext0);
        emit NoteAdded(first + 1, t.commitments[1], t.ext.ciphertext1);

        if (t.exitShares != 0) {
            uint256 total = convertToAssets(t.exitShares);
            uint256 fee = t.ext.gasFee == 0 ? 0 : convertToAssets(t.ext.gasFee);
            // The fee's shares are burned but its ZERO stays: a donation to every remaining note.
            amount = total - fee;
            totalShares -= t.exitShares;
            totalBacking -= amount;
            emit VaultUpdated(totalBacking, totalShares);
            if (fee != 0) emit Donation(address(this), fee);
            if (amount != 0 && !toEscrow) {
                zero.safeTransfer(t.ext.recipient, amount);
                emit Exited(t.nullifiers[0], t.ext.recipient, amount, userShares);
            }
        }
    }

    function _mintShares(uint256 amount) internal returns (uint256 shares) {
        shares = convertToShares(amount);
        if (shares == 0) revert ZeroShares();
        totalBacking += amount;
        totalShares += shares;
        emit VaultUpdated(totalBacking, totalShares);
    }

    function _register(address owner, uint256 opk, bytes32 viewKey) internal {
        if (opk == 0 || opk >= NoteHash.FIELD) revert NotAFieldElement();
        keysOf[owner] = Keys(opk, viewKey);
        emit KeysRegistered(owner, opk, viewKey);
    }

    /// @dev The last two are the EIP-712 domain separator the owner's wallet signed under, as 128-bit halves.
    function _publicInputs(Transaction memory t) internal view returns (bytes32[] memory inputs) {
        inputs = new bytes32[](9);
        inputs[0] = bytes32(t.root);
        inputs[1] = bytes32(t.nullifiers[0]);
        inputs[2] = bytes32(t.nullifiers[1]);
        inputs[3] = bytes32(t.commitments[0]);
        inputs[4] = bytes32(t.commitments[1]);
        inputs[5] = bytes32(t.exitShares);
        inputs[6] = bytes32(extDataHash(t.ext));
        bytes32 domain = _domainSeparatorV4();
        inputs[7] = domain >> 128;
        inputs[8] = bytes32(uint256(uint128(uint256(domain))));
    }
}
