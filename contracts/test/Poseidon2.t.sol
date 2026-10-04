// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Poseidon2Hasher} from "../src/Poseidon2Hasher.sol";
import {OpaquePool} from "../src/OpaquePool.sol";
import {IHasher} from "../src/interfaces/IHasher.sol";
import {IVerifier} from "../src/interfaces/IVerifier.sol";
import {MockVerifier, MockERC20} from "./mocks/Mocks.sol";

/// @dev Exposes the permutation so it can be checked against Barretenberg's own test vector.
contract Poseidon2Harness is Poseidon2Hasher {
    function perm(uint256 a, uint256 b, uint256 c, uint256 d) external pure returns (uint256, uint256, uint256, uint256) {
        return _perm(a, b, c, d);
    }
}

/// Reference values below were printed by Noir (nargo 1.0.0-beta.11, `poseidon` v0.1.1) from the circuit's own
/// functions, so these tests pin the contract's hash and tree to the circuit.
contract Poseidon2Test is Test {
    Poseidon2Harness h;

    function setUp() public {
        h = new Poseidon2Harness();
    }

    function test_permutationMatchesBarretenbergVector() public view {
        (uint256 a, uint256 b, uint256 c, uint256 d) = h.perm(0, 1, 2, 3);
        assertEq(a, 0x01bd538c2ee014ed5141b29e9ae240bf8db3fe5b9a38629a9647cf8d76c01737);
        assertEq(b, 0x239b62e7db98aa3a2a8f6a0d2fa1709e7a35959aa6c7034814d9daa90cbac662);
        assertEq(c, 0x04cbb44c61d928ed06808456bf758cbf0c18d1e15a7b6dbc8245fa7515d5e3cb);
        assertEq(d, 0x2e11c5cff2a22c64d01304b778d78f6998eff1ab73163a35603f54794c30847a);
    }

    function test_hash2MatchesNoir() public view {
        assertEq(h.hash2(1, 2), 0x038682aa1cb5ae4e0a3f13da432a95c77c5c111f6f030faf9cad641ce1ed7383);
        assertEq(h.hash2(0, 0), 0x0b63a53787021a4a962a452c2921b3663aff1ffd8d5510540f8e659e782956f1);
        uint256 z = uint256(keccak256("opaque")) % 21888242871839275222246405745257275088548364400416034343698204186575808495617;
        assertEq(h.hash2(z, z), 0x0f6c6519e112e89a57d5d374496c621ca877d7c2765976561459fbd9b1daeedc);
    }

    function test_hash4MatchesNoir() public view {
        assertEq(h.hash4(1, 2, 3, 4), 0x130bf204a32cac1f0ace56c78b731aa3809f06df2731ebcf6b3464a15788b1b9);
        assertEq(h.hash4(1, 12345, 1, 999000000000000000), 0x04d1b475d7b6ee08f8c9283dff7afc6cf68d14aacc78a1f55d286938f2ec5a9d);
    }

    function test_gasIsReasonable() public {
        uint256 g = gasleft();
        h.hash2(1, 2);
        uint256 used = g - gasleft();
        emit log_named_uint("hash2 gas", used);
        assertLt(used, 60_000);
    }
}

/// The pool's tree must produce the same roots as the circuit's Merkle path function.
contract PoolTreeMatchesCircuitTest is Test {
    OpaquePool pool;

    function setUp() public {
        Poseidon2Hasher hasher = new Poseidon2Hasher();
        MockVerifier verifier = new MockVerifier();
        MockERC20 token = new MockERC20();
        OpaquePool.CapSchedule memory cap =
            OpaquePool.CapSchedule({initialCap: 10 ether, stepAmount: 10 ether, stepInterval: 1 days, maxCap: 100 ether});
        pool = new OpaquePool(IHasher(address(hasher)), IVerifier(address(verifier)), address(token), address(0xAA), 0, cap);
        token.mint(address(this), 1e30);
        token.approve(address(pool), type(uint256).max);
    }

    function test_emptyRootMatchesCircuit() public view {
        assertEq(pool.currentRoot(), 0x0ae5127e85ed8bc5bb8b69fdc41b3a35e0eea45834ac2b2b433975cc014ebb92);
    }

    function test_firstLeafRootMatchesCircuit() public {
        // Shielding 0.999e12 tokens into an empty pool mints 0.999e18 shares (first deposit x 1e6 offset), so the
        // note is asset id 1, amount 0.999e18, stub 12345. Same leaf as the circuit vector.
        pool.shield(12345, 999_000_000_000, "");
        assertEq(pool.currentRoot(), 0x28f0c18ed00c5247f6d5cd0fd3bcc1ce8d4984239fa55e9c4637b0955bf29c18);
    }
}
