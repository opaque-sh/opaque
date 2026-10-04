// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployPool} from "../script/DeployPool.s.sol";
import {OpaquePool} from "../src/OpaquePool.sol";
import {MockERC20} from "./mocks/Mocks.sol";

/// The deploy script's settings are what we decided for launch, and what it deploys works.
contract DeployPoolTest is Test {
    function test_deployedSettings() public {
        MockERC20 token = new MockERC20();
        address guardian = makeAddr("guardian");
        DeployPool d = new DeployPool();
        (,, OpaquePool pool) = d.deploy(address(token), guardian);

        assertEq(pool.token(), address(token));
        assertEq(pool.guardian(), guardian);
        assertEq(pool.exitFeeBps(), 30);
        assertEq(pool.depositCap(), 50_000_000e18, "starting cap is 5% of 1B");
        vm.warp(block.timestamp + 7 days);
        assertEq(pool.depositCap(), 55_000_000e18, "plus 0.5% a week");
        vm.warp(block.timestamp + 365 days);
        assertEq(pool.depositCap(), 100_000_000e18, "ceiling is 10%");
    }

    function test_poolWorksWithItsOwnHasherAndVerifier() public {
        MockERC20 token = new MockERC20();
        DeployPool d = new DeployPool();
        (,, OpaquePool pool) = d.deploy(address(token), address(this));
        token.mint(address(this), 1_000e18);
        token.approve(address(pool), type(uint256).max);
        pool.shroud(12345, 1_000e18, "");
        assertEq(pool.units(), 1_000e18 * 1_000_000);
    }
}
