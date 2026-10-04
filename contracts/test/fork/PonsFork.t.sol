// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {OpaquePool} from "../../src/OpaquePool.sol";
import {OpaqueHarvester} from "../../src/OpaqueHarvester.sol";
import {IOpaquePool} from "../../src/interfaces/IOpaquePool.sol";
import {IHasher} from "../../src/interfaces/IHasher.sol";
import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {IPonsFactory, IPonsFeeEscrow, PonsLaunchedToken} from "../../src/pons/IPons.sol";
import {MockHasher, MockVerifier} from "../mocks/Mocks.sol";

interface IFactoryPoolManager {
    function poolManager() external view returns (address);
}

/// @notice Runs the harvester against the LIVE Pons contracts on Robinhood Chain, on a fork.
///         Skipped unless ROBINHOOD_RPC is set. Use it to check the Pons calls and the graduated-pool buy
///         (the hook accepting a swap from a contract, the pool key, the fee maths) before deploying for real.
///
///           ROBINHOOD_RPC=<rpc url> forge test --match-path contracts/test/fork/PonsFork.t.sol -vv
///
///         It deploys a throwaway OpaquePool and OpaqueHarvester for an existing Pons v2 token that has already
///         graduated (default: the token below, override with PONS_TOKEN), feeds the harvester ETH, and calls
///         `harvest`. Nothing is sent on-chain.
contract PonsForkTest is Test {
    address constant FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    address constant FEE_ESCROW = 0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e;
    address constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address constant DEFAULT_TOKEN = 0x7dbf38976f6D3b9c529e7D9484A71898B409eE6a;

    address token;
    OpaquePool pool;
    OpaqueHarvester harvester;
    address team = makeAddr("team");
    address owner = makeAddr("owner");

    function setUp() public {
        string memory rpc = vm.envOr("ROBINHOOD_RPC", string(""));
        if (bytes(rpc).length == 0) vm.skip(true);
        vm.createSelectFork(rpc);

        token = vm.envOr("PONS_TOKEN", DEFAULT_TOKEN);
        OpaquePool.CapSchedule memory cap =
            OpaquePool.CapSchedule({initialCap: 1e30, stepAmount: 0, stepInterval: 1 days, maxCap: 1e30});
        pool = new OpaquePool(
            IHasher(address(new MockHasher())), IVerifier(address(new MockVerifier())), token, owner, 0, cap
        );

        OpaqueHarvester.Config memory c;
        c.poolManager = IPoolManager(POOL_MANAGER);
        c.ponsFactory = IPonsFactory(FACTORY);
        c.feeEscrow = IPonsFeeEscrow(FEE_ESCROW);
        c.pool = IOpaquePool(address(pool));
        harvester = new OpaqueHarvester(c, token, owner, team, 5_000);
    }

    /// The PoolManager address used here is the one Pons' factory itself points at.
    function test_fork_poolManagerIsPonsOwn() public view {
        assertEq(IFactoryPoolManager(FACTORY).poolManager(), POOL_MANAGER);
    }

    /// The constructor reads Pons' real record and the harvester can read a live price.
    function test_fork_readsLiveRecordAndPrice() public view {
        PonsLaunchedToken memory t = IPonsFactory(FACTORY).getLaunchedToken(token);
        console.log("phase", t.phase);
        console.log("curve", t.curve);
        console.log("creatorTaxBps", t.creatorTaxBps);
        assertTrue(t.exists);
        assertEq(t.pairToken, address(0));
        assertEq(address(harvester.curve()), t.curve);
        uint256 spot = harvester.spotPrice();
        console.log("spot tokens per ETH (1e18)", spot);
        assertGt(spot, 0, "no price: the pool key is probably wrong, or the token has not graduated");
    }

    /// The real buy: ETH in, tokens out through Pons' pool and hook, donated to the throwaway pool.
    function test_fork_harvestBuysThroughPonsPoolAndDonates() public {
        PonsLaunchedToken memory t = IPonsFactory(FACTORY).getLaunchedToken(token);
        if (t.phase != 2) {
            console.log("token has not graduated, pool buy not tested");
            return;
        }
        vm.deal(address(harvester), 1 ether); // ETH sent directly counts for the holders' side
        vm.roll(block.number + 1);
        uint256 ethBefore = address(harvester).balance;
        uint256 donated = harvester.harvest();

        console.log("ETH spent", ethBefore - address(harvester).balance);
        console.log("tokens donated", donated);
        console.log("pool backing", pool.backing());
        assertGt(donated, 0, "no buy happened: read the BuySkipped event and the logs");
        assertEq(pool.backing(), donated);
        assertEq(_balanceOf(address(harvester)), 0, "no tokens left behind");
    }

    /// A second buy in a later block works, which shows the price average and the per-block limit behave live.
    function test_fork_secondBuyNextBlock() public {
        PonsLaunchedToken memory t = IPonsFactory(FACTORY).getLaunchedToken(token);
        if (t.phase != 2) return;
        vm.deal(address(harvester), 2 ether);
        vm.roll(block.number + 1);
        harvester.harvest();
        uint256 first = pool.backing();
        vm.roll(block.number + 1);
        harvester.harvest();
        assertGt(pool.backing(), first);
    }

    function _balanceOf(address who) internal view returns (uint256) {
        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSignature("balanceOf(address)", who));
        require(ok && ret.length >= 32, "balanceOf");
        return abi.decode(ret, (uint256));
    }
}
