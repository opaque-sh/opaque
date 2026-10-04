// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {OpaquePool} from "../src/OpaquePool.sol";
import {IOpaquePool} from "../src/interfaces/IOpaquePool.sol";
import {IHasher} from "../src/interfaces/IHasher.sol";
import {IVerifier} from "../src/interfaces/IVerifier.sol";
import {Poseidon2Hasher} from "../src/Poseidon2Hasher.sol";
import {HonkVerifier} from "../src/HonkVerifier.sol";
import {MockERC20} from "./mocks/Mocks.sol";

/// @notice The whole path with nothing mocked: the real Poseidon2 hasher, the real generated verifier, a note built
///         by the TypeScript SDK (sdk/e2e.ts) and a proof made by `bb` for it.
///
///         The numbers come from contracts/test/fixtures/e2e_scenario.json (written by `npm run e2e:gen` in sdk/).
///         The proof comes from circuits/pool/scripts/prove_e2e.sh. Until e2e_proof.bin exists, the tests that need
///         it show as skipped, not passed.
contract OpaquePoolE2ETest is Test {
    string constant SCENARIO = "contracts/test/fixtures/e2e_scenario.json";
    string constant PROOF = "contracts/test/fixtures/e2e_proof.bin";
    string constant INPUTS = "contracts/test/fixtures/e2e_public_inputs.bin";

    OpaquePool pool;
    MockERC20 token;
    string json;
    address alice = makeAddr("alice");

    function setUp() public {
        token = new MockERC20();
        OpaquePool.CapSchedule memory cap =
            OpaquePool.CapSchedule({initialCap: 1e30, stepAmount: 0, stepInterval: 1 days, maxCap: 1e30});
        pool = new OpaquePool(
            IHasher(address(new Poseidon2Hasher())), IVerifier(address(new HonkVerifier())), address(token), address(0xAA), 30, cap
        );
        token.mint(alice, 1e30);
        vm.prank(alice);
        token.approve(address(pool), type(uint256).max);
        json = vm.readFile(SCENARIO);
    }

    function _u(string memory key) internal view returns (uint256) {
        return vm.parseJsonUint(json, key);
    }

    function _shroud() internal {
        vm.prank(alice);
        pool.shroud(_u(".stub"), _u(".shroudTokens"), "");
    }

    function _transaction() internal view returns (IOpaquePool.Transaction memory t) {
        t.root = _u(".root");
        t.nullifiers = [_u(".nullifier0"), _u(".nullifier1")];
        t.commitments = [_u(".commitment0"), _u(".commitment1")];
        t.assetId = _u(".assetId");
        t.exitAmount = _u(".exitAmount");
        t.ext = IOpaquePool.ExtData({
            recipient: vm.parseJsonAddress(json, ".recipient"),
            caller: vm.parseJsonAddress(json, ".caller"),
            fee: _u(".relayerFee"),
            data: "",
            ciphertext0: vm.parseJsonBytes(json, ".ciphertext0"),
            ciphertext1: vm.parseJsonBytes(json, ".ciphertext1")
        });
    }

    /// The SDK's tree, hash and note model agree with the contract: same shares, same root.
    function test_sdkNoteMatchesPool() public {
        _shroud();
        assertEq(pool.units(), _u(".shares"), "shares minted differ from the SDK's");
        assertEq(pool.currentRoot(), _u(".root"), "pool root differs from the SDK's root");
    }

    /// The public inputs the pool builds for this transaction are exactly what the proof was made for.
    function test_publicInputsMatchProof() public {
        if (!vm.exists(INPUTS)) {
            vm.skip(true, "no e2e proof yet, run circuits/pool/scripts/prove_e2e.sh");
        }
        bytes memory raw = vm.readFileBinary(INPUTS);
        bytes32[] memory fromPool = pool.publicInputs(_transaction());
        assertEq(raw.length, fromPool.length * 32);
        for (uint256 i = 0; i < fromPool.length; i++) {
            bytes32 w;
            assembly {
                w := mload(add(add(raw, 32), mul(i, 32)))
            }
            assertEq(w, fromPool[i], "public input differs from the proof's");
        }
    }

    /// Shroud, then unshroud part of it with a real proof, through the real verifier.
    function test_unshroudWithRealProof() public {
        if (!vm.exists(PROOF)) {
            vm.skip(true, "no e2e proof yet, run circuits/pool/scripts/prove_e2e.sh");
        }
        _shroud();
        bytes memory proof = vm.readFileBinary(PROOF);
        IOpaquePool.Transaction memory t = _transaction();
        address bob = t.ext.recipient;

        uint256 unitsBefore = pool.units();
        uint256 backingBefore = pool.backing();
        uint256 tokens = pool.tokensForShares(t.exitAmount);
        uint256 fee = pool.exitFeeFor(tokens);

        pool.transact(t, proof);

        assertEq(token.balanceOf(bob), tokens - fee, "recipient payout");
        assertEq(pool.units(), unitsBefore - t.exitAmount, "shares burned");
        assertEq(pool.backing(), backingBefore - (tokens - fee), "the fee stays in backing");
        assertEq(token.balanceOf(address(pool)), pool.backing(), "pool holds exactly its backing");
        assertTrue(pool.nullifierSpent(t.nullifiers[0]));
        assertTrue(pool.nullifierSpent(t.nullifiers[1]));
        assertEq(pool.nextIndex(), 3, "one shroud leaf plus two outputs");
    }

    function test_replayRejected() public {
        if (!vm.exists(PROOF)) {
            vm.skip(true, "no e2e proof yet, run circuits/pool/scripts/prove_e2e.sh");
        }
        _shroud();
        bytes memory proof = vm.readFileBinary(PROOF);
        IOpaquePool.Transaction memory t = _transaction();
        pool.transact(t, proof);
        vm.expectRevert(OpaquePool.NullifierUsed.selector);
        pool.transact(t, proof);
    }

    /// A relayer cannot redirect the payout: changing the recipient changes the ext data hash, so the proof fails.
    function test_redirectedRecipientRejected() public {
        if (!vm.exists(PROOF)) {
            vm.skip(true, "no e2e proof yet, run circuits/pool/scripts/prove_e2e.sh");
        }
        _shroud();
        bytes memory proof = vm.readFileBinary(PROOF);
        IOpaquePool.Transaction memory t = _transaction();
        t.ext.recipient = address(0xBAD);
        // the generated verifier reverts with its own error (SumcheckFailed) instead of returning false
        vm.expectRevert();
        pool.transact(t, proof);
    }

    /// A relayer cannot swap the ciphertexts either.
    function test_swappedCiphertextRejected() public {
        if (!vm.exists(PROOF)) {
            vm.skip(true, "no e2e proof yet, run circuits/pool/scripts/prove_e2e.sh");
        }
        _shroud();
        bytes memory proof = vm.readFileBinary(PROOF);
        IOpaquePool.Transaction memory t = _transaction();
        t.ext.ciphertext0 = hex"deadbeef";
        vm.expectRevert(); // see test_redirectedRecipientRejected
        pool.transact(t, proof);
    }
}
