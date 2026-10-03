// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHasher} from "../../src/interfaces/IHasher.sol";
import {IVerifier} from "../../src/interfaces/IVerifier.sol";

uint256 constant FIELD = 21888242871839275222246405745257275088548364400416034343698204186575808495617;

/// @dev Keccak stand-in for Poseidon2. Tests only.
contract MockHasher is IHasher {
    function hash2(uint256 a, uint256 b) external pure returns (uint256) {
        return uint256(keccak256(abi.encode(a, b))) % FIELD;
    }

    function hash4(uint256 a, uint256 b, uint256 c, uint256 d) external pure returns (uint256) {
        return uint256(keccak256(abi.encode(a, b, c, d))) % FIELD;
    }
}

/// @dev Accepts or rejects every proof, depending on a switch. Tests only.
contract MockVerifier is IVerifier {
    bool public accept = true;

    function setAccept(bool a) external {
        accept = a;
    }

    function verify(bytes calldata, bytes32[] calldata) external view returns (bool) {
        return accept;
    }
}

contract MockERC20 {
    string public name = "Flagship";
    string public symbol = "OPA";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    uint256 public feeBps; // set above zero to simulate a fee-on-transfer token
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function setFeeBps(uint256 f) external {
        feeBps = f;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address s, uint256 amount) external returns (bool) {
        allowance[msg.sender][s] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _move(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        if (a != type(uint256).max) allowance[from][msg.sender] = a - amount;
        _move(from, to, amount);
        return true;
    }

    function _move(address from, address to, uint256 amount) internal {
        balanceOf[from] -= amount;
        uint256 fee = (amount * feeBps) / 10_000;
        balanceOf[to] += amount - fee;
        totalSupply -= fee;
    }
}
