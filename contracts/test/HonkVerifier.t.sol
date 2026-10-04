// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {HonkVerifier} from "../src/HonkVerifier.sol";
import {IVerifier} from "../src/interfaces/IVerifier.sol";

/// @notice Checks the generated UltraHonk verifier against a real proof made by `bb` for the example witness in
///         circuits/pool/Prover.toml. This proves the verifier contract accepts a real proof and takes the public
///         inputs in the pool's order. It does NOT prove the pool and the circuit agree on a live transaction:
///         the example uses its own tree, so see ROADMAP for the end-to-end test that still has to be written.
contract HonkVerifierTest is Test {
    HonkVerifier verifier;
    bytes proof;
    bytes32[] inputs;

    function setUp() public {
        verifier = new HonkVerifier();
        proof = vm.readFileBinary("contracts/test/fixtures/example_proof.bin");
        bytes memory raw = vm.readFileBinary("contracts/test/fixtures/example_public_inputs.bin");
        assertEq(raw.length, 8 * 32, "the example has 8 public inputs");
        for (uint256 i = 0; i < 8; i++) {
            bytes32 w;
            assembly {
                w := mload(add(add(raw, 32), mul(i, 32)))
            }
            inputs.push(w);
        }
    }

    function test_realProofVerifies() public view {
        assertTrue(verifier.verify(proof, inputs));
    }

    /// The pool talks to the verifier through its own IVerifier interface. Same call, same answer.
    function test_verifiesThroughPoolInterface() public view {
        assertTrue(IVerifier(address(verifier)).verify(proof, inputs));
    }

    function test_gasForVerify() public {
        uint256 g = gasleft();
        verifier.verify(proof, inputs);
        emit log_named_uint("gas used by verify", g - gasleft());
    }

    /// Changing any one public input must break the proof, each of the eight in turn.
    function test_anyChangedInputIsRejected() public view {
        for (uint256 i = 0; i < 8; i++) {
            bytes32[] memory bad = new bytes32[](8);
            for (uint256 j = 0; j < 8; j++) bad[j] = inputs[j];
            bad[i] = bytes32(uint256(bad[i]) ^ 1);
            bool ok;
            try verifier.verify(proof, bad) returns (bool r) {
                ok = r;
            } catch {
                ok = false;
            }
            assertFalse(ok, "a changed public input was accepted");
        }
    }

    /// Flipping a byte in the proof must break it, at several places.
    function test_tamperedProofIsRejected() public view {
        uint256[5] memory spots = [uint256(40), 700, 4000, 9000, 16000];
        for (uint256 s = 0; s < spots.length; s++) {
            bytes memory bad = proof;
            bad = bytes.concat(proof);
            bad[spots[s]] = bytes1(uint8(bad[spots[s]]) ^ 0x01);
            bool ok;
            try verifier.verify(bad, inputs) returns (bool r) {
                ok = r;
            } catch {
                ok = false;
            }
            assertFalse(ok, "a tampered proof was accepted");
        }
    }

    function test_wrongInputCountReverts() public {
        bytes32[] memory few = new bytes32[](7);
        for (uint256 i = 0; i < 7; i++) few[i] = inputs[i];
        vm.expectRevert();
        verifier.verify(proof, few);
    }
}
