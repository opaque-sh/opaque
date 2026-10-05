// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {OpaqueHarvester} from "../src/OpaqueHarvester.sol";
import {IOpaquePool} from "../src/interfaces/IOpaquePool.sol";
import {IPonsFactory, IPonsFeeEscrow} from "../src/pons/IPons.sol";

/// @notice Deploys the harvester for an existing pool. Run it after the pool, before moving the Pons fee recipient.
///
///   TOKEN=0x... POOL=0x... TEAM_RECIPIENT=0x... forge script contracts/script/DeployHarvester.s.sol \
///     --rpc-url <rpc> --account <keystore name> --sender <deployer address> --broadcast
///
/// Optional: OWNER (default: the deployer), TEAM_SHARE_BPS (default 5000 = 50%).
/// The Pons addresses are the live Robinhood Chain ones, checked against Pons' own factory in the fork test.
contract DeployHarvester is Script {
    address constant FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    address constant FEE_ESCROW = 0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e;
    address constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;

    function run() external {
        address token = vm.envAddress("TOKEN");
        address pool = vm.envAddress("POOL");
        address team = vm.envAddress("TEAM_RECIPIENT");
        address owner = vm.envOr("OWNER", msg.sender);
        uint256 teamShareBps = vm.envOr("TEAM_SHARE_BPS", uint256(5000));

        require(token.code.length != 0, "TOKEN is not a contract on this chain");
        require(pool.code.length != 0, "POOL is not a contract on this chain");
        require(team != address(0), "TEAM_RECIPIENT is zero");

        OpaqueHarvester.Config memory c;
        c.poolManager = IPoolManager(POOL_MANAGER);
        c.ponsFactory = IPonsFactory(FACTORY);
        c.feeEscrow = IPonsFeeEscrow(FEE_ESCROW);
        c.pool = IOpaquePool(pool);

        vm.startBroadcast();
        OpaqueHarvester harvester = new OpaqueHarvester(c, token, owner, team, teamShareBps);
        vm.stopBroadcast();

        console2.log("chain id", block.chainid);
        console2.log("token", token);
        console2.log("pool", pool);
        console2.log("owner", owner);
        console2.log("team recipient", team);
        console2.log("team share bps", teamShareBps);
        console2.log("OpaqueHarvester", address(harvester));
    }
}
