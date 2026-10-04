// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {OpaquePool} from "../src/OpaquePool.sol";
import {IHasher} from "../src/interfaces/IHasher.sol";
import {IVerifier} from "../src/interfaces/IVerifier.sol";
import {Poseidon2Hasher} from "../src/Poseidon2Hasher.sol";
import {HonkVerifier} from "../src/HonkVerifier.sol";

/// @notice Deploys the hasher, the verifier and the pool. The harvester is a separate step.
///
///   TOKEN=0x... forge script contracts/script/DeployPool.s.sol --rpc-url <rpc> --account <keystore name> --broadcast
///
/// Settings (all fixed in the contracts after this runs, nothing can be changed later):
///   exit fee 0.3% of each unshroud, deposit cap starting at 0.5% of a 1B supply, rising 0.5% a week to 10%.
/// The guardian (can only pause NEW shrouds) is the deployer unless GUARDIAN is set.
contract DeployPool is Script {
    uint256 constant ONE_TOKEN = 1e18;
    uint256 constant EXIT_FEE_BPS = 30;

    function schedule() public pure returns (OpaquePool.CapSchedule memory) {
        return OpaquePool.CapSchedule({
            initialCap: uint128(5_000_000 * ONE_TOKEN),
            stepAmount: uint128(5_000_000 * ONE_TOKEN),
            stepInterval: 7 days,
            maxCap: uint128(100_000_000 * ONE_TOKEN)
        });
    }

    /// Split out so a test can run it without broadcasting.
    function deploy(address token, address guardian)
        public
        returns (Poseidon2Hasher hasher, HonkVerifier verifier, OpaquePool pool)
    {
        hasher = new Poseidon2Hasher();
        verifier = new HonkVerifier();
        pool = new OpaquePool(
            IHasher(address(hasher)), IVerifier(address(verifier)), token, guardian, EXIT_FEE_BPS, schedule()
        );
    }

    function run() external {
        address token = vm.envAddress("TOKEN");
        require(token.code.length != 0, "TOKEN is not a contract on this chain");
        address guardian = vm.envOr("GUARDIAN", msg.sender);

        vm.startBroadcast();
        (Poseidon2Hasher hasher, HonkVerifier verifier, OpaquePool pool) = deploy(token, guardian);
        vm.stopBroadcast();

        console2.log("chain id", block.chainid);
        console2.log("token", token);
        console2.log("guardian", guardian);
        console2.log("Poseidon2Hasher", address(hasher));
        console2.log("HonkVerifier", address(verifier));
        console2.log("OpaquePool", address(pool));
        console2.log("pool launch time", pool.launchTime());
        console2.log("deposit cap now", pool.depositCap());
        console2.log("exit fee bps", pool.exitFeeBps());
    }
}
