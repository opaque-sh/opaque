// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {OpaquePool} from "../src/OpaquePool.sol";
import {IOpaquePool} from "../src/interfaces/IOpaquePool.sol";
import {IHasher} from "../src/interfaces/IHasher.sol";
import {IVerifier} from "../src/interfaces/IVerifier.sol";
import {MockHasher, MockVerifier, MockERC20, FIELD} from "./mocks/Mocks.sol";

contract PoolBase is Test {
    OpaquePool pool;
    MockHasher hasher;
    MockVerifier verifier;
    MockERC20 token;

    address guardian = makeAddr("guardian");
    address feeSink = makeAddr("feeSink");
    address alice = makeAddr("alice");
    address relayer = makeAddr("relayer");
    address bob = makeAddr("bob");

    uint256 constant SHIELD_FEE_BPS = 10; // 0.10%
    uint256 constant EXIT_FEE = 0.0005 ether;

    function setUp() public virtual {
        hasher = new MockHasher();
        verifier = new MockVerifier();
        token = new MockERC20();
        OpaquePool.CapSchedule memory ethCap =
            OpaquePool.CapSchedule({initialCap: 10 ether, stepAmount: 10 ether, stepInterval: 1 days, maxCap: 100 ether});
        OpaquePool.CapSchedule memory flagCap = OpaquePool.CapSchedule({
            initialCap: 1_000e18, stepAmount: 1_000e18, stepInterval: 1 days, maxCap: 10_000e18
        });
        pool = new OpaquePool(
            IHasher(address(hasher)),
            IVerifier(address(verifier)),
            address(token),
            guardian,
            feeSink,
            SHIELD_FEE_BPS,
            EXIT_FEE,
            ethCap,
            flagCap
        );
        vm.deal(alice, 1_000 ether);
        token.mint(alice, 100_000e18);
        vm.prank(alice);
        token.approve(address(pool), type(uint256).max);
    }

    function _ext(address recipient, address caller, uint256 fee) internal pure returns (IOpaquePool.ExtData memory e) {
        e = IOpaquePool.ExtData({
            recipient: recipient, caller: caller, fee: fee, data: "", ciphertext0: hex"aa", ciphertext1: hex"bb"
        });
    }

    function _tx(uint256 root, uint256 nf0, uint256 nf1, uint256 assetId, uint256 exitAmount, IOpaquePool.ExtData memory e)
        internal
        pure
        returns (IOpaquePool.Transaction memory t)
    {
        t.root = root;
        t.nullifiers = [nf0, nf1];
        t.commitments = [uint256(111), uint256(222)];
        t.assetId = assetId;
        t.exitAmount = exitAmount;
        t.ext = e;
    }

    function _shieldEth(uint256 amount) internal returns (uint32) {
        vm.prank(alice);
        return pool.shield{value: amount}(address(0), 12345, amount, hex"01");
    }

    function _shieldFlag(uint256 amount) internal returns (uint32) {
        vm.prank(alice);
        return pool.shield(address(token), 12345, amount, hex"01");
    }
}

contract TreeTest is PoolBase {
    /// Recompute the root off-chain style for the first N leaves, using the same hash.
    function _rootOf(uint256[] memory leaves) internal view returns (uint256) {
        uint256[] memory level = new uint256[](leaves.length);
        uint256 z = pool.ZERO_LEAF();
        uint256 n = leaves.length;
        for (uint256 i = 0; i < n; i++) level[i] = leaves[i];
        for (uint256 d = 0; d < 24; d++) {
            uint256 next = (n + 1) / 2;
            uint256[] memory up = new uint256[](next == 0 ? 1 : next);
            for (uint256 i = 0; i < next; i++) {
                uint256 l = level[2 * i];
                uint256 r = 2 * i + 1 < n ? level[2 * i + 1] : z;
                up[i] = hasher.hash2(l, r);
            }
            level = up;
            n = next;
            z = hasher.hash2(z, z);
        }
        return level[0];
    }

    function test_emptyRootIsKnownAndNonZero() public view {
        assertTrue(pool.currentRoot() != 0);
        assertTrue(pool.isKnownRoot(pool.currentRoot()));
        assertFalse(pool.isKnownRoot(0));
    }

    function test_rootMatchesRecomputation() public {
        uint256[] memory leaves = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            _shieldEth(1 ether);
            leaves[i] = hasher.hash4(1, 12345, 1, 1 ether - (1 ether * SHIELD_FEE_BPS) / 10_000);
        }
        assertEq(pool.currentRoot(), _rootOf(leaves));
        assertEq(pool.nextIndex(), 3);
    }

    function test_rootHistoryWindow() public {
        _shieldEth(1 ether);
        uint256 first = pool.currentRoot();
        assertTrue(pool.isKnownRoot(first));
        for (uint256 i = 0; i < 63; i++) _shieldEthSmall();
        assertTrue(pool.isKnownRoot(first));
        _shieldEthSmall();
        assertFalse(pool.isKnownRoot(first));
    }

    function _shieldEthSmall() internal {
        vm.prank(alice);
        pool.shield{value: 0.01 ether}(address(0), 1, 0.01 ether, "");
    }
}

contract ShieldTest is PoolBase {
    function test_shieldEth_feeAndCommitment() public {
        uint32 idx = _shieldEth(1 ether);
        uint256 fee = (1 ether * SHIELD_FEE_BPS) / 10_000;
        assertEq(idx, 0);
        assertEq(pool.ethNotes(), 1 ether - fee);
        assertEq(pool.ethFeesAccrued(), fee);
        assertEq(address(pool).balance, 1 ether);
    }

    function test_shieldEth_wrongValueReverts() public {
        vm.prank(alice);
        vm.expectRevert(OpaquePool.BadAmount.selector);
        pool.shield{value: 1 ether}(address(0), 1, 2 ether, "");
    }

    function test_shieldFlagship_firstDepositIsOneToOneTimesOffset() public {
        _shieldFlag(100e18);
        assertEq(pool.flagshipBacking(), 100e18);
        assertEq(pool.flagshipUnits(), (100e18 * 1e6) / 1);
        assertEq(token.balanceOf(address(pool)), 100e18);
    }

    function test_unknownAssetReverts() public {
        vm.prank(alice);
        vm.expectRevert(OpaquePool.UnknownAsset.selector);
        pool.shield(address(0xdead), 1, 1, "");
    }

    function test_stubMustBeInField() public {
        vm.prank(alice);
        vm.expectRevert(OpaquePool.NotInField.selector);
        pool.shield{value: 1 ether}(address(0), FIELD, 1 ether, "");
    }

    function test_capEnforcedAndRisesOnSchedule() public {
        assertEq(pool.depositCap(address(0)), 10 ether);
        vm.prank(alice);
        vm.expectRevert(OpaquePool.CapExceeded.selector);
        pool.shield{value: 11 ether}(address(0), 1, 11 ether, "");

        vm.warp(block.timestamp + 1 days);
        assertEq(pool.depositCap(address(0)), 20 ether);
        _shieldEth(11 ether);

        vm.warp(block.timestamp + 365 days);
        assertEq(pool.depositCap(address(0)), 100 ether);
    }

    function test_guardianCanOnlyPauseDeposits() public {
        vm.prank(alice);
        vm.expectRevert(OpaquePool.NotGuardian.selector);
        pool.setDepositsPaused(true);

        vm.prank(guardian);
        pool.setDepositsPaused(true);
        vm.prank(alice);
        vm.expectRevert(OpaquePool.DepositsPaused.selector);
        pool.shield{value: 1 ether}(address(0), 1, 1 ether, "");

        // exits still work while paused
        uint256 root = pool.currentRoot();
        IOpaquePool.Transaction memory t = _tx(root, 1, 2, 1, 0, _ext(address(0), address(0), 0));
        pool.transact(t, "");
    }

    function test_feeOnTransferTokenRejected() public {
        token.setFeeBps(100);
        vm.prank(alice);
        vm.expectRevert(OpaquePool.FeeOnTransferToken.selector);
        pool.shield(address(token), 1, 10e18, "");
    }

    function test_ethRejectedWhenSentDirectly() public {
        vm.prank(alice);
        (bool ok,) = address(pool).call{value: 1 ether}("");
        assertFalse(ok);
    }

    function test_collectEthFeesGoesToSinkOnly() public {
        _shieldEth(5 ether);
        uint256 fee = pool.ethFeesAccrued();
        assertGt(fee, 0);
        vm.prank(bob);
        uint256 got = pool.collectEthFees();
        assertEq(got, fee);
        assertEq(feeSink.balance, fee);
        assertEq(pool.ethFeesAccrued(), 0);
        assertEq(pool.collectEthFees(), 0);
    }
}

contract TransactTest is PoolBase {
    function test_exitEth_splitsPayoutRelayerAndProtocolFee() public {
        _shieldEth(5 ether);
        uint256 root = pool.currentRoot();
        uint256 relayerFee = 0.001 ether;
        IOpaquePool.Transaction memory t =
            _tx(root, 1, 2, 1, 2 ether, _ext(bob, relayer, relayerFee));

        uint256 feesBefore = pool.ethFeesAccrued();
        uint256 notesBefore = pool.ethNotes();
        vm.prank(relayer);
        pool.transact(t, hex"cafe");

        assertEq(bob.balance, 2 ether - relayerFee - EXIT_FEE);
        assertEq(relayer.balance, relayerFee);
        assertEq(pool.ethNotes(), notesBefore - 2 ether);
        assertEq(pool.ethFeesAccrued(), feesBefore + EXIT_FEE);
        assertTrue(pool.nullifierSpent(1));
        assertTrue(pool.nullifierSpent(2));
        assertEq(pool.nextIndex(), 3); // 1 shield + 2 outputs
        assertEq(address(pool).balance, pool.ethNotes() + pool.ethFeesAccrued());
    }

    function test_doubleSpendReverts() public {
        _shieldEth(5 ether);
        uint256 root = pool.currentRoot();
        IOpaquePool.Transaction memory t = _tx(root, 1, 2, 1, 1 ether, _ext(bob, address(0), 0));
        pool.transact(t, "");
        t.nullifiers = [uint256(2), uint256(3)];
        vm.expectRevert(OpaquePool.NullifierUsed.selector);
        pool.transact(t, "");
    }

    function test_sameNullifierTwiceInOneTxReverts() public {
        uint256 root = pool.currentRoot();
        IOpaquePool.Transaction memory t = _tx(root, 7, 7, 1, 0, _ext(address(0), address(0), 0));
        vm.expectRevert(OpaquePool.DuplicateNullifier.selector);
        pool.transact(t, "");
    }

    function test_unknownRootReverts() public {
        IOpaquePool.Transaction memory t = _tx(999, 1, 2, 1, 0, _ext(address(0), address(0), 0));
        vm.expectRevert(OpaquePool.UnknownRoot.selector);
        pool.transact(t, "");
    }

    function test_badProofReverts() public {
        verifier.setAccept(false);
        uint256 root = pool.currentRoot();
        IOpaquePool.Transaction memory t = _tx(root, 1, 2, 1, 0, _ext(address(0), address(0), 0));
        vm.expectRevert(OpaquePool.InvalidProof.selector);
        pool.transact(t, "");
        assertFalse(pool.nullifierSpent(1)); // revert rolled back
    }

    function test_wrongCallerReverts() public {
        uint256 root = pool.currentRoot();
        IOpaquePool.Transaction memory t = _tx(root, 1, 2, 1, 0, _ext(address(0), relayer, 0));
        vm.prank(bob);
        vm.expectRevert(OpaquePool.WrongCaller.selector);
        pool.transact(t, "");
    }

    function test_feeAboveExitReverts() public {
        _shieldEth(5 ether);
        uint256 root = pool.currentRoot();
        IOpaquePool.Transaction memory t = _tx(root, 1, 2, 1, 0.0006 ether, _ext(bob, address(0), 0.0002 ether));
        vm.expectRevert(OpaquePool.FeeTooHigh.selector);
        pool.transact(t, "");
    }

    function test_feeWithoutExitReverts() public {
        uint256 root = pool.currentRoot();
        IOpaquePool.Transaction memory t = _tx(root, 1, 2, 1, 0, _ext(bob, address(0), 1));
        vm.expectRevert(OpaquePool.BadExit.selector);
        pool.transact(t, "");
    }

    function test_exitTargetDataRejectedForNow() public {
        uint256 root = pool.currentRoot();
        IOpaquePool.ExtData memory e = _ext(bob, address(0), 0);
        e.data = hex"01";
        IOpaquePool.Transaction memory t = _tx(root, 1, 2, 1, 0, e);
        vm.expectRevert(OpaquePool.ExitTargetsNotSupported.selector);
        pool.transact(t, "");
    }

    function test_privateTransferInsertsTwoNotesWithoutExit() public {
        _shieldEth(5 ether);
        uint256 root = pool.currentRoot();
        IOpaquePool.Transaction memory t = _tx(root, 1, 2, 1, 0, _ext(address(0), address(0), 0));
        uint256 notes = pool.ethNotes();
        pool.transact(t, "");
        assertEq(pool.ethNotes(), notes);
        assertEq(pool.nextIndex(), 3);
    }

    function test_publicInputsOrderAndExtBinding() public {
        uint256 root = pool.currentRoot();
        IOpaquePool.Transaction memory t = _tx(root, 5, 6, 2, 0, _ext(bob, relayer, 0));
        bytes32[] memory p = pool.publicInputs(t);
        assertEq(p.length, 8);
        assertEq(uint256(p[0]), root);
        assertEq(uint256(p[1]), 5);
        assertEq(uint256(p[2]), 6);
        assertEq(uint256(p[3]), 111);
        assertEq(uint256(p[4]), 222);
        assertEq(uint256(p[5]), 2);
        assertEq(uint256(p[6]), 0);
        assertEq(uint256(p[7]), pool.extDataHash(t.ext));

        // changing the recipient changes the bound hash
        IOpaquePool.ExtData memory e2 = _ext(alice, relayer, 0);
        assertTrue(pool.extDataHash(e2) != pool.extDataHash(t.ext));
    }
}

contract FlagshipTest is PoolBase {
    function test_donationRaisesSharePriceForExit() public {
        _shieldFlag(100e18);
        uint256 shares = pool.flagshipUnits();

        // donate another 100 tokens. Note holders now own 200 tokens (minus rounding).
        vm.prank(alice);
        pool.donate(address(token), 100e18);
        assertEq(pool.flagshipBacking(), 200e18);

        uint256 root = pool.currentRoot();
        IOpaquePool.Transaction memory t = _tx(root, 1, 2, 2, shares, _ext(bob, address(0), 0));
        pool.transact(t, "");

        // virtual offset leaves a dust amount behind, never more than a few tokens' worth of wei
        assertApproxEqAbs(token.balanceOf(bob), 200e18, 1e12);
        assertLe(token.balanceOf(bob), 200e18);
        assertEq(pool.flagshipUnits(), 0);
        assertEq(token.balanceOf(address(pool)), pool.flagshipBacking());
    }

    function test_laterDepositorDoesNotStealDonations() public {
        _shieldFlag(100e18);
        vm.prank(alice);
        pool.donate(address(token), 100e18);
        uint256 sharesBefore = pool.flagshipUnits();
        _shieldFlag(200e18); // buys in at the new price, so gets about half the first holder's shares
        uint256 minted = pool.flagshipUnits() - sharesBefore;
        assertApproxEqRel(minted, sharesBefore, 1e6); // within 1e-12
    }

    function test_donateEthAssetReverts() public {
        vm.prank(alice);
        vm.expectRevert(OpaquePool.UnknownAsset.selector);
        pool.donate(address(0), 1);
    }

    function test_donateWorksWhilePaused() public {
        vm.prank(guardian);
        pool.setDepositsPaused(true);
        vm.prank(alice);
        pool.donate(address(token), 1e18);
        assertEq(pool.flagshipBacking(), 1e18);
    }

    function test_inflationAttackIsUneconomic() public {
        // attacker donates before anyone deposits, victim then shields a smaller amount
        vm.startPrank(alice);
        pool.donate(address(token), 500e18);
        vm.stopPrank();
        uint256 sharesBefore = pool.flagshipUnits();
        _shieldFlag(100e18);
        uint256 minted = pool.flagshipUnits() - sharesBefore;
        assertGt(minted, 0);
        // victim's shares are worth at least 99.9% of what they put in
        assertGe(pool.tokensForShares(minted), 99.9e18);
    }
}

/// @dev Invariant: the pool's real balances always cover what its accounting says it owes.
contract Handler is Test {
    OpaquePool public pool;
    MockERC20 public token;
    address public user = address(0xA11CE);
    uint256 public ethLedger; // note value the handler believes exists
    uint256 public shareLedger;
    uint256 nf = 1000;

    constructor(OpaquePool p, MockERC20 t) {
        pool = p;
        token = t;
        vm.deal(user, 1_000_000 ether);
        t.mint(user, 1e30);
        vm.prank(user);
        t.approve(address(p), type(uint256).max);
    }

    function shieldEth(uint256 amount) external {
        amount = bound(amount, 1e6, 5 ether);
        uint256 cap = pool.depositCap(address(0));
        if (pool.ethNotes() + pool.ethFeesAccrued() + amount > cap) return;
        vm.prank(user);
        pool.shield{value: amount}(address(0), 1, amount, "");
        ethLedger += amount - (amount * pool.ethShieldFeeBps()) / 10_000;
    }

    function shieldFlag(uint256 amount) external {
        amount = bound(amount, 1e12, 100e18);
        if (pool.flagshipBacking() + amount > pool.depositCap(address(token))) return;
        uint256 before = pool.flagshipUnits();
        vm.prank(user);
        pool.shield(address(token), 1, amount, "");
        shareLedger += pool.flagshipUnits() - before;
    }

    function donate(uint256 amount) external {
        amount = bound(amount, 1, 50e18);
        vm.prank(user);
        pool.donate(address(token), amount);
    }

    function exitEth(uint256 amount) external {
        if (ethLedger <= pool.ethExitFee()) return;
        amount = bound(amount, pool.ethExitFee(), ethLedger);
        _exit(1, amount);
        ethLedger -= amount;
    }

    function exitFlag(uint256 amount) external {
        if (shareLedger == 0) return;
        amount = bound(amount, 1, shareLedger);
        _exit(2, amount);
        shareLedger -= amount;
    }

    function collect() external {
        pool.collectEthFees();
    }

    function warp(uint256 secs) external {
        vm.warp(block.timestamp + bound(secs, 0, 3 days));
    }

    function _exit(uint256 assetId, uint256 amount) internal {
        IOpaquePool.Transaction memory t;
        t.root = pool.currentRoot();
        t.nullifiers = [nf++, nf++];
        t.commitments = [uint256(1), uint256(2)];
        t.assetId = assetId;
        t.exitAmount = amount;
        t.ext = IOpaquePool.ExtData(address(0xB0B), address(0), 0, "", "", "");
        pool.transact(t, "");
    }
}

contract PoolInvariants is PoolBase {
    Handler handler;

    function setUp() public override {
        super.setUp();
        handler = new Handler(pool, token);
        targetContract(address(handler));
    }

    function invariant_ethBalanceCoversAccounting() public view {
        assertEq(address(pool).balance, pool.ethNotes() + pool.ethFeesAccrued());
    }

    function invariant_flagshipBalanceEqualsBacking() public view {
        assertEq(token.balanceOf(address(pool)), pool.flagshipBacking());
    }

    function invariant_ethNotesMatchLedger() public view {
        assertEq(pool.ethNotes(), handler.ethLedger());
    }

    function invariant_sharesMatchLedger() public view {
        assertEq(pool.flagshipUnits(), handler.shareLedger());
    }
}
