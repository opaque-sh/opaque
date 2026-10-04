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
    address alice = makeAddr("alice");
    address relayer = makeAddr("relayer");
    address bob = makeAddr("bob");

    uint256 constant EXIT_FEE_BPS = 30; // 0.3% unshield fee

    function setUp() public virtual {
        hasher = new MockHasher();
        verifier = new MockVerifier();
        token = new MockERC20();
        OpaquePool.CapSchedule memory cap = OpaquePool.CapSchedule({
            initialCap: 1_000e18, stepAmount: 1_000e18, stepInterval: 1 days, maxCap: 10_000e18
        });
        pool = new OpaquePool(IHasher(address(hasher)), IVerifier(address(verifier)), address(token), guardian, EXIT_FEE_BPS, cap);
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

    function _shield(uint256 amount) internal returns (uint32) {
        vm.prank(alice);
        return pool.shield(12345, amount, hex"01");
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
            uint256 before = pool.units();
            _shield(10e18);
            leaves[i] = hasher.hash4(1, 12345, 1, pool.units() - before);
        }
        assertEq(pool.currentRoot(), _rootOf(leaves));
        assertEq(pool.nextIndex(), 3);
    }

    function test_rootHistoryWindow() public {
        _shield(1e18);
        uint256 first = pool.currentRoot();
        assertTrue(pool.isKnownRoot(first));
        for (uint256 i = 0; i < 63; i++) _shieldSmall();
        assertTrue(pool.isKnownRoot(first));
        _shieldSmall();
        assertFalse(pool.isKnownRoot(first));
    }

    function _shieldSmall() internal {
        vm.prank(alice);
        pool.shield(1, 1e15, "");
    }
}

contract ShieldTest is PoolBase {
    function test_firstDepositIsOneToOneTimesOffset() public {
        uint32 idx = _shield(100e18);
        assertEq(idx, 0);
        assertEq(pool.backing(), 100e18);
        assertEq(pool.units(), (100e18 * 1e6) / 1);
        assertEq(token.balanceOf(address(pool)), 100e18);
    }

    function test_noShieldFee() public {
        _shield(100e18);
        assertEq(token.balanceOf(address(pool)), 100e18);
        assertEq(pool.backing(), 100e18);
    }

    function test_stubMustBeInField() public {
        vm.prank(alice);
        vm.expectRevert(OpaquePool.NotInField.selector);
        pool.shield(FIELD, 1e18, "");
    }

    function test_zeroAmountReverts() public {
        vm.prank(alice);
        vm.expectRevert(OpaquePool.BadAmount.selector);
        pool.shield(1, 0, "");
    }

    function test_capEnforcedAndRisesOnSchedule() public {
        assertEq(pool.depositCap(), 1_000e18);
        vm.prank(alice);
        vm.expectRevert(OpaquePool.CapExceeded.selector);
        pool.shield(1, 1_001e18, "");

        vm.warp(block.timestamp + 1 days);
        assertEq(pool.depositCap(), 2_000e18);
        _shield(1_001e18);

        vm.warp(block.timestamp + 365 days);
        assertEq(pool.depositCap(), 10_000e18);
    }

    function test_guardianCanOnlyPauseDeposits() public {
        vm.prank(alice);
        vm.expectRevert(OpaquePool.NotGuardian.selector);
        pool.setDepositsPaused(true);

        vm.prank(guardian);
        pool.setDepositsPaused(true);
        vm.prank(alice);
        vm.expectRevert(OpaquePool.DepositsPaused.selector);
        pool.shield(1, 1e18, "");

        // transfers still work while paused
        uint256 root = pool.currentRoot();
        IOpaquePool.Transaction memory t = _tx(root, 1, 2, 1, 0, _ext(address(0), address(0), 0));
        pool.transact(t, "");
    }

    function test_feeOnTransferTokenRejected() public {
        token.setFeeBps(100);
        vm.prank(alice);
        vm.expectRevert(OpaquePool.FeeOnTransferToken.selector);
        pool.shield(1, 10e18, "");
    }

    function test_ethRejectedWhenSentDirectly() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(pool).call{value: 1 ether}("");
        assertFalse(ok);
    }
}

contract TransactTest is PoolBase {
    function test_exit_splitsPayoutRelayerAndFee() public {
        _shield(100e18);
        uint256 shares = pool.units();
        uint256 root = pool.currentRoot();
        uint256 exitShares = shares / 2; // about 50 tokens
        uint256 relayerShares = exitShares / 100; // 1% of the exit goes to the relayer
        IOpaquePool.Transaction memory t = _tx(root, 1, 2, 1, exitShares, _ext(bob, relayer, relayerShares));

        uint256 tokens = pool.tokensForShares(exitShares);
        uint256 relayerTokens = (tokens * relayerShares) / exitShares;
        uint256 fee = (tokens * EXIT_FEE_BPS) / 10_000;
        assertGt(fee, 0);
        vm.prank(relayer);
        pool.transact(t, hex"cafe");

        assertEq(token.balanceOf(bob), tokens - relayerTokens - fee);
        assertEq(token.balanceOf(relayer), relayerTokens);
        assertEq(pool.units(), shares - exitShares);
        // the fee stays as backing
        assertEq(pool.backing(), 100e18 - (tokens - fee));
        assertEq(token.balanceOf(address(pool)), pool.backing());
        assertTrue(pool.nullifierSpent(1));
        assertTrue(pool.nullifierSpent(2));
        assertEq(pool.nextIndex(), 3); // 1 shield + 2 outputs
    }

    function test_feeRaisesSharePriceForRemainingHolders() public {
        _shield(100e18);
        uint256 shares = pool.units();
        uint256 valueBefore = pool.tokensForShares(shares / 2);
        uint256 root = pool.currentRoot();
        IOpaquePool.Transaction memory t = _tx(root, 1, 2, 1, shares / 2, _ext(bob, address(0), 0));
        pool.transact(t, "");
        // the remaining half of the shares is now worth more than half of the original backing minus nothing taken
        assertGt(pool.tokensForShares(shares - shares / 2), valueBefore);
    }

    function test_relayerFeePlusPoolFeeAboveExitReverts() public {
        _shield(100e18);
        uint256 root = pool.currentRoot();
        uint256 exitShares = pool.units() / 100;
        // the relayer asks for 99.8% of the exit, the pool fee takes 0.3%: together over 100%
        uint256 relayerShares = (exitShares * 9980) / 10_000;
        IOpaquePool.Transaction memory t = _tx(root, 1, 2, 1, exitShares, _ext(bob, relayer, relayerShares));
        vm.prank(relayer);
        vm.expectRevert(OpaquePool.FeeTooHigh.selector);
        pool.transact(t, "");
    }

    function test_tinyExitIsNeverStuck() public {
        _shield(100e18);
        uint256 root = pool.currentRoot();
        // a few shares are worth almost nothing, the fee rounds down with them and the exit still works
        IOpaquePool.Transaction memory t = _tx(root, 1, 2, 1, 3, _ext(bob, address(0), 0));
        pool.transact(t, "");
        assertTrue(pool.nullifierSpent(1));
        assertEq(token.balanceOf(address(pool)), pool.backing());
    }

    function test_exitFeeForMatchesBps() public view {
        assertEq(pool.exitFeeBps(), EXIT_FEE_BPS);
        assertEq(pool.exitFeeFor(1_000e18), 3e18);
        assertEq(pool.exitFeeFor(0), 0);
    }

    function test_exitFeeCeilingEnforced() public {
        OpaquePool.CapSchedule memory cap = OpaquePool.CapSchedule({
            initialCap: 1e30, stepAmount: 0, stepInterval: 1 days, maxCap: 1e30
        });
        uint256 max = pool.MAX_EXIT_FEE_BPS();
        new OpaquePool(IHasher(address(hasher)), IVerifier(address(verifier)), address(token), guardian, max, cap);
        vm.expectRevert(bytes("exit fee too high"));
        new OpaquePool(IHasher(address(hasher)), IVerifier(address(verifier)), address(token), guardian, max + 1, cap);
    }

    function test_relayerFeeAboveExitReverts() public {
        _shield(100e18);
        uint256 root = pool.currentRoot();
        IOpaquePool.Transaction memory t = _tx(root, 1, 2, 1, 1e24, _ext(bob, address(0), 1e24 + 1));
        vm.expectRevert(OpaquePool.FeeTooHigh.selector);
        pool.transact(t, "");
    }

    function test_exitMoreThanAllSharesReverts() public {
        _shield(100e18);
        uint256 root = pool.currentRoot();
        IOpaquePool.Transaction memory t = _tx(root, 1, 2, 1, pool.units() + 1, _ext(bob, address(0), 0));
        vm.expectRevert(OpaquePool.InsufficientBacking.selector);
        pool.transact(t, "");
    }

    function test_unknownAssetReverts() public {
        uint256 root = pool.currentRoot();
        IOpaquePool.Transaction memory t = _tx(root, 1, 2, 2, 0, _ext(address(0), address(0), 0));
        vm.expectRevert(OpaquePool.UnknownAsset.selector);
        pool.transact(t, "");
    }

    function test_doubleSpendReverts() public {
        _shield(100e18);
        uint256 root = pool.currentRoot();
        IOpaquePool.Transaction memory t = _tx(root, 1, 2, 1, pool.units() / 2, _ext(bob, address(0), 0));
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
        _shield(100e18);
        uint256 root = pool.currentRoot();
        IOpaquePool.Transaction memory t = _tx(root, 1, 2, 1, 0, _ext(address(0), address(0), 0));
        uint256 backing = pool.backing();
        uint256 shares = pool.units();
        pool.transact(t, "");
        assertEq(pool.backing(), backing);
        assertEq(pool.units(), shares);
        assertEq(pool.nextIndex(), 3);
    }

    function test_publicInputsOrderAndExtBinding() public {
        uint256 root = pool.currentRoot();
        IOpaquePool.Transaction memory t = _tx(root, 5, 6, 1, 0, _ext(bob, relayer, 0));
        bytes32[] memory p = pool.publicInputs(t);
        assertEq(p.length, 8);
        assertEq(uint256(p[0]), root);
        assertEq(uint256(p[1]), 5);
        assertEq(uint256(p[2]), 6);
        assertEq(uint256(p[3]), 111);
        assertEq(uint256(p[4]), 222);
        assertEq(uint256(p[5]), 1);
        assertEq(uint256(p[6]), 0);
        assertEq(uint256(p[7]), pool.extDataHash(t.ext));

        // changing the recipient changes the bound hash
        IOpaquePool.ExtData memory e2 = _ext(alice, relayer, 0);
        assertTrue(pool.extDataHash(e2) != pool.extDataHash(t.ext));
    }
}

contract YieldTest is PoolBase {
    function test_donationRaisesSharePriceForExit() public {
        _shield(100e18);
        uint256 shares = pool.units();

        // donate another 100 tokens. Note holders now own 200 tokens (minus rounding).
        vm.prank(alice);
        pool.donate(100e18);
        assertEq(pool.backing(), 200e18);

        uint256 root = pool.currentRoot();
        IOpaquePool.Transaction memory t = _tx(root, 1, 2, 1, shares, _ext(bob, address(0), 0));
        pool.transact(t, "");

        // bob gets everything minus the 0.3% fee, which stays behind as backing
        uint256 fee = (200e18 * EXIT_FEE_BPS) / 10_000;
        assertApproxEqAbs(token.balanceOf(bob), 200e18 - fee, 1e12);
        assertLe(token.balanceOf(bob), 200e18 - fee);
        assertEq(pool.units(), 0);
        assertEq(token.balanceOf(address(pool)), pool.backing());
    }

    function test_laterDepositorDoesNotStealDonations() public {
        _shield(100e18);
        vm.prank(alice);
        pool.donate(100e18);
        uint256 sharesBefore = pool.units();
        _shield(200e18); // buys in at the new price, so gets about half the first holder's shares
        uint256 minted = pool.units() - sharesBefore;
        assertApproxEqRel(minted, sharesBefore, 1e6); // within 1e-12
    }

    function test_donateZeroReverts() public {
        vm.prank(alice);
        vm.expectRevert(OpaquePool.BadAmount.selector);
        pool.donate(0);
    }

    function test_donateWorksWhilePaused() public {
        vm.prank(guardian);
        pool.setDepositsPaused(true);
        vm.prank(alice);
        pool.donate(1e18);
        assertEq(pool.backing(), 1e18);
    }

    function test_inflationAttackIsUneconomic() public {
        // attacker donates before anyone deposits, victim then shields a smaller amount
        vm.startPrank(alice);
        pool.donate(500e18);
        vm.stopPrank();
        uint256 sharesBefore = pool.units();
        _shield(100e18);
        uint256 minted = pool.units() - sharesBefore;
        assertGt(minted, 0);
        // victim's shares are worth at least 99.9% of what they put in
        assertGe(pool.tokensForShares(minted), 99.9e18);
    }
}

/// @dev Invariant: the pool's real balance always equals its accounting, and shares match the ledger.
contract Handler is Test {
    OpaquePool public pool;
    MockERC20 public token;
    address public user = address(0xA11CE);
    uint256 public shareLedger;
    uint256 nf = 1000;

    constructor(OpaquePool p, MockERC20 t) {
        pool = p;
        token = t;
        t.mint(user, 1e30);
        vm.prank(user);
        t.approve(address(p), type(uint256).max);
    }

    function shield(uint256 amount) external {
        amount = bound(amount, 1e12, 100e18);
        if (pool.backing() + amount > pool.depositCap()) return;
        uint256 before = pool.units();
        vm.prank(user);
        pool.shield(1, amount, "");
        shareLedger += pool.units() - before;
    }

    function donate(uint256 amount) external {
        amount = bound(amount, 1, 50e18);
        vm.prank(user);
        pool.donate(amount);
    }

    function exitShares(uint256 amount) external {
        if (shareLedger == 0) return;
        amount = bound(amount, 1, shareLedger);
        IOpaquePool.Transaction memory t;
        t.root = pool.currentRoot();
        t.nullifiers = [nf++, nf++];
        t.commitments = [uint256(1), uint256(2)];
        t.assetId = 1;
        t.exitAmount = amount;
        t.ext = IOpaquePool.ExtData(address(0xB0B), address(0), 0, "", "", "");
        pool.transact(t, "");
        shareLedger -= amount;
    }

    function warp(uint256 secs) external {
        vm.warp(block.timestamp + bound(secs, 0, 3 days));
    }
}

contract PoolInvariants is PoolBase {
    Handler handler;

    function setUp() public override {
        super.setUp();
        handler = new Handler(pool, token);
        targetContract(address(handler));
    }

    function invariant_balanceEqualsBacking() public view {
        assertEq(token.balanceOf(address(pool)), pool.backing());
    }

    function invariant_sharesMatchLedger() public view {
        assertEq(pool.units(), handler.shareLedger());
    }
}
