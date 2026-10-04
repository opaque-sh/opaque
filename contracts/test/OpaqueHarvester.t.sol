// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";

import {OpaquePool} from "../src/OpaquePool.sol";
import {OpaqueHarvester} from "../src/OpaqueHarvester.sol";
import {IOpaquePool} from "../src/interfaces/IOpaquePool.sol";
import {IHasher} from "../src/interfaces/IHasher.sol";
import {IVerifier} from "../src/interfaces/IVerifier.sol";
import {IPonsFactory, IPonsFeeEscrow} from "../src/pons/IPons.sol";
import {MockHasher, MockVerifier, MockERC20} from "./mocks/Mocks.sol";
import {MockPonsEscrow, MockPonsFactory, MockPonsCurve, Refuser} from "./mocks/PonsMocks.sol";

contract HarvesterBase is Test {
    MockERC20 token;
    OpaquePool pool;
    MockPonsEscrow escrow;
    MockPonsFactory factory;
    MockPonsCurve curve;
    OpaqueHarvester harvester;

    address owner = makeAddr("owner");
    address team = makeAddr("team");
    address keeper = makeAddr("keeper");
    address stranger = makeAddr("stranger");

    uint256 constant TEAM_SHARE = 5_000;

    function _deployPool() internal {
        OpaquePool.CapSchedule memory cap = OpaquePool.CapSchedule({
            initialCap: 1e30, stepAmount: 0, stepInterval: 1 days, maxCap: 1e30
        });
        pool = new OpaquePool(
            IHasher(address(new MockHasher())), IVerifier(address(new MockVerifier())), address(token), owner, 0, cap
        );
    }

    function _new(IPoolManager pm, address owner_, address team_, uint256 share) internal returns (OpaqueHarvester) {
        OpaqueHarvester.Config memory c;
        c.poolManager = pm;
        c.ponsFactory = IPonsFactory(address(factory));
        c.feeEscrow = IPonsFeeEscrow(address(escrow));
        c.pool = IOpaquePool(address(pool));
        return new OpaqueHarvester(c, address(token), owner_, team_, share);
    }

    function _deployHarvester(IPoolManager pm) internal {
        harvester = _new(pm, owner, team, TEAM_SHARE);
        // Pons names the harvester as the creator fee recipient
        vm.prank(factory.creatorFeeRecipient());
        factory.transferCreatorFeeRecipient(address(token), address(harvester));
    }

    function _fees(uint256 amount) internal {
        vm.deal(address(this), address(this).balance + amount);
        escrow.credit{value: amount}(address(harvester));
    }
}

contract CurveHarvesterTest is HarvesterBase {
    address deployerWallet = makeAddr("deployerWallet");

    function setUp() public {
        token = new MockERC20();
        _deployPool();
        escrow = new MockPonsEscrow();
        curve = new MockPonsCurve(token, 10 ether, 800_000_000e18);
        token.mint(address(curve), 800_000_000e18);
        factory = new MockPonsFactory(address(token), address(curve), deployerWallet, address(0));
        _deployHarvester(IPoolManager(address(0xdead)));
        vm.roll(100);
    }

    // ------------------------------------------------------------ constructor

    function test_constructor_readsPonsRecord() public view {
        assertEq(address(harvester.curve()), address(curve));
        assertEq(harvester.token(), address(token));
        assertEq(harvester.teamShareBps(), TEAM_SHARE);
        assertEq(harvester.owner(), owner);
    }

    function test_constructor_rejectsNonPonsToken() public {
        factory.setExists(false);
        vm.expectRevert(OpaqueHarvester.NotAPonsLaunch.selector);
        _new(IPoolManager(address(0xdead)), owner, team, TEAM_SHARE);
    }

    function test_constructor_rejectsNonEthPair() public {
        factory.setPairToken(address(0x1234));
        vm.expectRevert(OpaqueHarvester.NotAnEthPair.selector);
        _new(IPoolManager(address(0xdead)), owner, team, TEAM_SHARE);
    }

    function test_constructor_rejectsTeamShareAbove100Percent() public {
        vm.expectRevert(OpaqueHarvester.BadTeamShare.selector);
        _new(IPoolManager(address(0xdead)), owner, team, 10_001);
    }

    // ------------------------------------------------------------ harvest

    function test_harvest_paysTeamAndDonatesBoughtTokens() public {
        _fees(2 ether);
        uint256 backingBefore = pool.backing();
        vm.prank(keeper);
        uint256 donated = harvester.harvest();

        assertEq(team.balance, 1 ether, "team gets its half");
        assertGt(donated, 0);
        assertEq(pool.backing(), backingBefore + donated, "donated to the pool");
        assertEq(token.balanceOf(address(harvester)), 0, "no tokens left behind");
        assertEq(token.balanceOf(address(pool)), pool.backing());
        // the buy is capped to ~0.5% impact: 10 ETH reserve gives a 0.025 ETH cap, the rest waits
        assertApproxEqAbs(address(harvester).balance, 1 ether - 0.025 ether, 0.001 ether);
        assertEq(harvester.teamOwed(), 0);
    }

    function test_harvest_buySizeIsImpactCapped() public {
        _fees(100 ether);
        (uint256 q0,) = curve.getReserves();
        vm.prank(keeper);
        harvester.harvest();
        (uint256 q1,) = curve.getReserves();
        uint256 spent = q1 - q0; // reserve grows by the post-fee quote
        assertLe(spent, (q0 * 50) / 20_000 + 1);
    }

    function test_harvest_oneBuyPerBlock() public {
        _fees(2 ether);
        harvester.harvest();
        uint256 backing = pool.backing();
        harvester.harvest(); // same block
        assertEq(pool.backing(), backing, "no second buy in the block");
        vm.roll(block.number + 1);
        harvester.harvest();
        assertGt(pool.backing(), backing, "buys again next block");
    }

    function test_harvest_priceMovedAgainstUsSkipsBuyAndKeepsEth() public {
        _fees(2 ether);
        harvester.harvest(); // seeds the price average
        vm.roll(block.number + 1);
        _fees(2 ether);
        uint256 ethBefore = address(harvester).balance;
        uint256 backing = pool.backing();
        // someone halves the tokens on the curve: tokens now cost double what the average says
        (uint256 q, uint256 t) = curve.getReserves();
        curve.setReserves(q, t / 2);

        vm.expectEmit(false, false, false, false);
        emit OpaqueHarvester.BuySkipped(0);
        harvester.harvest();

        assertEq(pool.backing(), backing, "nothing donated");
        // the new fees still arrived (the team's half left, the holders' half stayed)
        assertGt(address(harvester).balance, ethBefore);
    }

    function test_harvest_averageStepIsClamped() public {
        _fees(1 ether);
        harvester.harvest();
        uint256 ema0 = harvester.tokensPerEthEma();
        (uint256 q, uint256 t) = curve.getReserves();
        vm.roll(block.number + 1);
        curve.setReserves(q, t * 10); // spot jumps 10x
        harvester.harvest(); // folds the previous block's price in
        vm.roll(block.number + 1);
        harvester.harvest();
        uint256 ema2 = harvester.tokensPerEthEma();
        // at most ~1.25% per block (10% step, weight 1/8)
        assertLe(ema2, (ema0 * 10_130 * 10_130) / (10_000 * 10_000));
    }

    function test_harvest_noBuyWhenCurveReadyToGraduate() public {
        curve.setReady(true);
        _fees(2 ether);
        uint256 backing = pool.backing();
        harvester.harvest();
        assertEq(pool.backing(), backing);
        assertEq(team.balance, 1 ether, "team still paid");
    }

    function test_harvest_noBuyWhileSwept() public {
        factory.setPhase(1);
        _fees(2 ether);
        uint256 backing = pool.backing();
        harvester.harvest();
        assertEq(pool.backing(), backing);
        assertEq(team.balance, 1 ether);
    }

    function test_harvest_callerTipIsCapped() public {
        _fees(2 ether);
        vm.fee(1 gwei);
        vm.txGasPrice(1 gwei);
        uint256 before = keeper.balance;
        vm.prank(keeper, keeper);
        harvester.harvest();
        uint256 tip = keeper.balance - before;
        assertGt(tip, 0);
        // never more than 0.5% of the ETH put to work (about 0.025 ETH)
        uint256 work = 0.026 ether;
        assertLe(tip, (work * 50) / 9_950);
    }

    function test_harvest_loopedCallsEarnNothing() public {
        // nothing to collect and nothing to spend: no tip, no revert
        vm.fee(1 gwei);
        vm.txGasPrice(1 gwei);
        uint256 before = keeper.balance;
        vm.prank(keeper, keeper);
        harvester.harvest();
        assertEq(keeper.balance, before);
    }

    function test_harvest_callsSweepOnCurvePhase() public {
        harvester.harvest();
        assertEq(curve.sweeps(), 1);
    }

    function test_teamShareZeroSendsEverythingToHolders() public {
        OpaqueHarvester h = _new(IPoolManager(address(0xdead)), owner, team, 0);
        vm.prank(address(harvester));
        factory.transferCreatorFeeRecipient(address(token), address(h));
        vm.deal(address(this), 1 ether);
        escrow.credit{value: 1 ether}(address(h));
        h.harvest();
        assertEq(team.balance, 0);
        assertEq(h.teamOwed(), 0);
    }

    // ------------------------------------------------------------ team

    function test_teamRecipientRefusingEthAccruesAndHarvestStillWorks() public {
        Refuser r = new Refuser();
        vm.prank(owner);
        harvester.setTeamRecipient(address(r));
        _fees(2 ether);
        harvester.harvest();
        assertEq(harvester.teamOwed(), 1 ether);
        assertGt(pool.backing(), 0);

        vm.prank(owner);
        harvester.setTeamRecipient(team); // pays what is owed
        assertEq(team.balance, 1 ether);
        assertEq(harvester.teamOwed(), 0);
    }

    function test_teamRecipientZeroAccruesUntilSet() public {
        vm.prank(owner);
        harvester.setTeamRecipient(address(0));
        _fees(2 ether);
        harvester.harvest();
        assertEq(harvester.teamOwed(), 1 ether);
        harvester.payTeam();
        assertEq(harvester.teamOwed(), 1 ether);
    }

    function test_onlyOwnerCanSetTeamRecipient() public {
        vm.prank(stranger);
        vm.expectRevert(OpaqueHarvester.NotOwner.selector);
        harvester.setTeamRecipient(stranger);
    }

    // ------------------------------------------------------------ successor

    function test_successor_waitsThenAnyoneExecutes() public {
        address next = makeAddr("next");
        vm.prank(owner);
        harvester.proposeSuccessor(next);

        vm.expectRevert(abi.encodeWithSelector(OpaqueHarvester.SuccessorNotReady.selector, harvester.successorReadyAt()));
        harvester.executeSuccessor();

        vm.warp(block.timestamp + 24 hours);
        vm.prank(stranger);
        harvester.executeSuccessor();

        assertEq(factory.creatorFeeRecipient(), next);
        assertEq(factory.lastTransferToken(), address(token));
        assertEq(harvester.pendingSuccessor(), address(0));
    }

    function test_successor_canBeCancelled() public {
        vm.startPrank(owner);
        harvester.proposeSuccessor(makeAddr("next"));
        harvester.cancelSuccessor();
        vm.stopPrank();
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(OpaqueHarvester.NoSuccessor.selector);
        harvester.executeSuccessor();
    }

    function test_successor_onlyOwnerProposes() public {
        vm.prank(stranger);
        vm.expectRevert(OpaqueHarvester.NotOwner.selector);
        harvester.proposeSuccessor(stranger);
    }

    function test_successor_zeroAddressRejected() public {
        vm.prank(owner);
        vm.expectRevert(OpaqueHarvester.NoSuccessor.selector);
        harvester.proposeSuccessor(address(0));
    }

    function test_renouncedOwnerFreezesEverything() public {
        vm.prank(owner);
        harvester.transferOwnership(address(0));
        vm.prank(owner);
        vm.expectRevert(OpaqueHarvester.NotOwner.selector);
        harvester.proposeSuccessor(makeAddr("next"));
        vm.prank(owner);
        vm.expectRevert(OpaqueHarvester.NotOwner.selector);
        harvester.setTeamRecipient(stranger);
    }

    function test_feesCreditedBeforeHandoverStayClaimable() public {
        _fees(2 ether);
        vm.prank(owner);
        harvester.proposeSuccessor(makeAddr("next"));
        vm.warp(block.timestamp + 24 hours);
        harvester.executeSuccessor();
        harvester.harvest();
        assertEq(team.balance, 1 ether);
    }

    // ------------------------------------------------------------ misc

    function test_buyStepOnlyCallableBySelf() public {
        vm.expectRevert(OpaqueHarvester.NotSelf.selector);
        harvester.buyStep(1, 1);
    }

    function test_unlockCallbackOnlyPoolManager() public {
        vm.expectRevert(OpaqueHarvester.NotPoolManager.selector);
        harvester.unlockCallback("");
    }

    function test_claimableCountsEscrowAndHeldEth() public {
        _fees(2 ether);
        assertEq(harvester.claimable(), 1 ether);
    }

    function test_directEthCountsForHolders() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(harvester).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(harvester.claimable(), 1 ether);
    }
}

/// @dev Adds liquidity to, and swaps against, a real Uniswap v4 PoolManager for the harvester tests.
contract V4Helper {
    IPoolManager public immutable pm;
    MockERC20 public immutable token;
    PoolKey public key;

    constructor(IPoolManager pm_, MockERC20 token_, PoolKey memory key_) {
        pm = pm_;
        token = token_;
        key = key_;
    }

    receive() external payable {}

    function addLiquidity(int24 lo, int24 hi, uint256 liq) external {
        pm.unlock(abi.encode(uint8(0), lo, hi, liq));
    }

    /// @dev A trade that pushes the price: ETH in, tokens out.
    function whaleBuy(uint256 ethIn) external {
        pm.unlock(abi.encode(uint8(1), int24(0), int24(0), ethIn));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "pm only");
        (uint8 op, int24 lo, int24 hi, uint256 amt) = abi.decode(data, (uint8, int24, int24, uint256));
        if (op == 0) {
            (BalanceDelta d,) =
                pm.modifyLiquidity(key, ModifyLiquidityParams(lo, hi, int256(amt), bytes32(0)), "");
            _pay(d);
        } else {
            BalanceDelta d = pm.swap(
                key, SwapParams(true, -int256(amt), TickMath.MIN_SQRT_PRICE + 1), ""
            );
            _pay(d);
        }
        return "";
    }

    function _pay(BalanceDelta d) internal {
        int128 a0 = BalanceDeltaLibrary.amount0(d);
        int128 a1 = BalanceDeltaLibrary.amount1(d);
        if (a0 < 0) pm.settle{value: uint256(uint128(-a0))}();
        if (a1 < 0) {
            pm.sync(key.currency1);
            token.transfer(address(pm), uint256(uint128(-a1)));
            pm.settle();
        }
        if (a0 > 0) pm.take(key.currency0, address(this), uint256(uint128(a0)));
        if (a1 > 0) pm.take(key.currency1, address(this), uint256(uint128(a1)));
    }
}

contract PoolHarvesterTest is HarvesterBase {
    IPoolManager pm;
    V4Helper helper;
    PoolKey key;
    address deployerWallet = makeAddr("deployerWallet");
    int24 constant TICK = 69_000; // about 990 tokens per ETH

    function setUp() public {
        token = new MockERC20();
        _deployPool();
        escrow = new MockPonsEscrow();
        curve = new MockPonsCurve(token, 10 ether, 800_000_000e18);
        token.mint(address(curve), 800_000_000e18);
        factory = new MockPonsFactory(address(token), address(curve), deployerWallet, address(0));
        factory.setPhase(2); // the pool exists, the hook is zero in this test

        pm = IPoolManager(deployCode("lib/v4-core/out/PoolManager.sol/PoolManager.json", abi.encode(address(this))));
        key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(token)),
            fee: 0,
            tickSpacing: 200,
            hooks: IHooks(address(0))
        });
        pm.initialize(key, TickMath.getSqrtPriceAtTick(TICK));

        helper = new V4Helper(pm, token, key);
        vm.deal(address(helper), 1_000 ether);
        token.mint(address(helper), 1e30);
        helper.addLiquidity(66_000, 72_000, 1e22);

        _deployHarvester(pm);
        vm.roll(100);
    }

    function test_spotPriceMatchesPool() public view {
        // price at tick 69000 is 1.0001^69000, about 990.7 tokens per ETH
        uint256 spot = harvester.spotPrice();
        assertApproxEqRel(spot, 990.7e18, 0.01e18);
    }

    function test_poolBuy_donatesTokensToPool() public {
        _fees(2 ether);
        uint256 backingBefore = pool.backing();
        uint256 ethBefore = address(harvester).balance;
        harvester.harvest();

        uint256 donated = pool.backing() - backingBefore;
        assertGt(donated, 0, "tokens donated");
        assertEq(token.balanceOf(address(harvester)), 0);
        assertEq(token.balanceOf(address(pool)), pool.backing());
        assertEq(team.balance, 1 ether);
        // spent about 0.8 ETH (the 0.5% impact cap on the active liquidity), the rest waits
        uint256 spent = (ethBefore + 2 ether) - 1 ether - address(harvester).balance;
        assertApproxEqAbs(spent, 0.8 ether, 0.05 ether);
        // got roughly the spot price for it (pool fee is zero in this test)
        assertApproxEqRel(donated, (spent * 990e18) / 1e18, 0.02e18);
    }

    function test_poolBuy_oneBuyPerBlockThenNextBlock() public {
        _fees(4 ether);
        harvester.harvest();
        uint256 backing = pool.backing();
        harvester.harvest();
        assertEq(pool.backing(), backing);
        vm.roll(block.number + 1);
        harvester.harvest();
        assertGt(pool.backing(), backing);
    }

    function test_poolBuy_skipsWhenPriceWasPushedAgainstUs() public {
        _fees(2 ether);
        harvester.harvest(); // seeds the average, buys once
        vm.roll(block.number + 1);
        // a whale buys tokens first, so tokens cost more than the average says
        helper.whaleBuy(60 ether);
        _fees(2 ether);
        uint256 backing = pool.backing();
        harvester.harvest();
        assertEq(pool.backing(), backing, "no buy at the pushed price");
    }

    function test_poolBuy_phaseOneMeansNoBuy() public {
        factory.setPhase(1);
        _fees(2 ether);
        uint256 backing = pool.backing();
        harvester.harvest();
        assertEq(pool.backing(), backing);
        assertEq(harvester.spotPrice(), 0);
    }
}
