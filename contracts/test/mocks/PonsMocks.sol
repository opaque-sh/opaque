// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PonsLaunchedToken} from "../../src/pons/IPons.sol";
import {MockERC20} from "./Mocks.sol";

/// @dev Stand-ins for the Pons v2 contracts the harvester calls. Tests only. Behaviour is a simple model, not a
///      copy of Pons: constant-product curve, escrow that pays out on claim, factory that records recipients.
contract MockPonsEscrow {
    mapping(address => uint256) public balanceOf;

    function credit(address recipient) external payable {
        balanceOf[recipient] += msg.value;
    }

    function claim() external {
        uint256 amount = balanceOf[msg.sender];
        balanceOf[msg.sender] = 0;
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "claim failed");
    }
}

contract MockPonsFactory {
    PonsLaunchedToken internal launch;
    address public memeHook;
    address public lastTransferToken;
    address public lastTransferTo;

    constructor(address token, address curve, address recipient, address pairToken) {
        launch.token = token;
        launch.curve = curve;
        launch.creatorFeeRecipient = recipient;
        launch.pairToken = pairToken;
        launch.poolFee = 0;
        launch.tickSpacing = 200;
        launch.exists = true;
    }

    function getLaunchedToken(address) external view returns (PonsLaunchedToken memory) {
        return launch;
    }

    function creatorFeeRecipient() external view returns (address) {
        return launch.creatorFeeRecipient;
    }

    function setPhase(uint8 p) external {
        launch.phase = p;
    }

    function setExists(bool e) external {
        launch.exists = e;
    }

    function setPairToken(address p) external {
        launch.pairToken = p;
    }

    function setHook(address h) external {
        memeHook = h;
    }

    function transferCreatorFeeRecipient(address token, address newRecipient) external {
        require(msg.sender == launch.creatorFeeRecipient, "not recipient");
        launch.creatorFeeRecipient = newRecipient;
        lastTransferToken = token;
        lastTransferTo = newRecipient;
    }
}

contract MockPonsCurve {
    MockERC20 public immutable token;
    uint256 public quoteReserve;
    uint256 public tokenReserve;
    uint256 public feeBps = 100;
    uint256 public creatorTaxBps;
    bool public readyToGraduate;
    uint256 public sweeps;

    constructor(MockERC20 t, uint256 quote, uint256 tokens) {
        token = t;
        quoteReserve = quote;
        tokenReserve = tokens;
    }

    function setReserves(uint256 q, uint256 t) external {
        quoteReserve = q;
        tokenReserve = t;
    }

    function setReady(bool r) external {
        readyToGraduate = r;
    }

    function getReserves() external view returns (uint256, uint256) {
        return (quoteReserve, tokenReserve);
    }

    function sweepFees(uint256) external {
        sweeps++;
    }

    function buy(uint256 quoteIn, uint256 minTokensOut, address recipient) external payable returns (uint256 out) {
        require(msg.value == quoteIn, "value");
        uint256 q = quoteIn - (quoteIn * (feeBps + creatorTaxBps)) / 10_000;
        out = (tokenReserve * q) / (quoteReserve + q);
        require(out >= minTokensOut, "slippage");
        quoteReserve += q;
        tokenReserve -= out;
        token.transfer(recipient, out);
    }
}

/// @dev A recipient that refuses ETH.
contract Refuser {
    receive() external payable {
        revert("no");
    }
}
