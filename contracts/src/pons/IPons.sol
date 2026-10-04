// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice The parts of Pons v2 that the harvester calls. Signatures come from the Pons v2 docs and from the v0
///         contracts. Check each against the verified ABI on the explorer before deploying (see docs/HARVESTER.md).

/// @dev Field order as listed in the Pons v2 docs. `phase`: 0 not graduated, 1 swept, 2 pool created, 3 rescued.
struct PonsLaunchedToken {
    address token;
    address curve;
    address deployer;
    address creatorFeeRecipient;
    address pairToken; // address(0) means native ETH
    uint256 graduationThreshold;
    uint24 poolFee;
    int24 tickSpacing;
    uint16 creatorTaxBps;
    bool buybackEnabled;
    uint8 phase;
    uint256 sweptQuote;
    uint256 sweptTokens;
    uint256 sweptAt;
    bool exists;
}

interface IPonsFactory {
    function getLaunchedToken(address token) external view returns (PonsLaunchedToken memory);
    function memeHook() external view returns (address);
    /// @dev Callable only by the token's current creator fee recipient. Takes effect at once.
    function transferCreatorFeeRecipient(address token, address newRecipient) external;
}

interface IPonsCurve {
    function buy(uint256 quoteIn, uint256 minTokensOut, address recipient) external payable returns (uint256 tokensOut);
    function getReserves() external view returns (uint256 quoteReserve, uint256 tokenReserve);
    function feeBps() external view returns (uint256);
    function creatorTaxBps() external view returns (uint256);
    function readyToGraduate() external view returns (bool);
    function sweepFees(uint256 minBuybackTokensOut) external;
}

interface IPonsHook {
    function sweepPoolFees(bytes32 poolId, uint256 minConversionQuoteOut, uint256 minBuybackTokensOut) external;
}

interface IPonsFeeEscrow {
    function balanceOf(address recipient) external view returns (uint256);
    function claim() external;
}
