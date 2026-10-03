// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";

import {PrivateVault} from "./PrivateVault.sol";
import {PonsSwapper} from "./PonsSwapper.sol";
import {IEntryPoint} from "./interfaces/IERC4337.sol";
import {IPonsFactory, IPonsFeeEscrow, IPonsHook, PonsLaunchedToken} from "./interfaces/IPons.sol";
import {IPonsFactoryRecipient} from "./FeeHarvester.sol";

/// @title FeeHarvesterV2
/// @notice ZERO's Pons creator fee recipient, taking over from the first harvester through its successor procedure.
///         Anyone can call `harvest`, which collects the creator fees Pons holds for ZERO and splits what it collects
///         in half: one half is owed to the team's recipient, the other keeps the vault's EntryPoint deposit at
///         `targetDeposit` and buys ZERO donated to the vault.
///
///         The holders' half buys in small steps: at most one buy per L1 block, each sized to move the price by no more
///         than 0.5%, and never more than 15% dearer than the vault's price average. A buy that small is not worth
///         sandwiching: pushing the price up before it and selling after costs the Pons fees on both legs, about 2%,
///         for at most the 0.5% it moves the price. What does not fit waits here for the next harvest.
///
///         The caller is only refunded the gas of a call that put ETH to work (deposited, or spent on ZERO), at no more
///         than twice the base fee, and never more than 0.5% of that work, so calling it in a loop earns nothing.
///
///         The owner can change the team's recipient, propose a successor (public, executable by anyone after
///         `SUCCESSOR_DELAY`), cancel it, hand ownership on, or renounce it.
contract FeeHarvesterV2 is PonsSwapper, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;

    /// @notice The team's share of the ETH each harvest collects.
    uint256 public constant TEAM_SHARE_BPS = 5_000;
    /// @notice The most a single buy may move ZERO's price.
    uint256 public constant MAX_IMPACT_BPS = 50;
    /// @notice A buy may not pay more than this above the vault's price average, after fees.
    uint256 public constant MAX_PREMIUM_BPS = 1_500;
    /// @notice The caller's refund never exceeds this share of the ETH a harvest puts to work.
    uint256 public constant CALLER_TIP_BPS = 50;
    /// @notice Gas refunded on top of what the call measures: the transaction's base cost and the refund itself.
    uint256 public constant GAS_OVERHEAD = 25_000;
    uint256 private constant BPS = 10_000;
    /// @dev A buy the market does not take within the limits is tried at most this many times, halving each time.
    uint256 private constant MAX_HALVINGS = 8;

    /// @notice How long a proposed successor waits before anyone can make it ZERO's fee recipient.
    uint256 public constant SUCCESSOR_DELAY = 24 hours;

    /// @notice May change the team's recipient, propose (and cancel) a successor, and hand ownership on. Zero once
    ///         renounced.
    address public owner;
    /// @notice Receives the team's half. While it is zero, or refuses the ETH, the share accrues in `teamOwed`.
    address public teamRecipient;
    /// @notice The team's share collected and not yet paid out. It is never spent on gas or ZERO.
    uint256 public teamOwed;
    /// @notice The contract proposed to take over as ZERO's creator fee recipient, and from when it can.
    address public pendingSuccessor;
    uint256 public successorReadyAt;
    /// @notice The L1 block of the latest buy: at most one per block.
    uint256 public lastBuyBlock;

    IEntryPoint public immutable entryPoint;
    IPonsFeeEscrow public immutable feeEscrow;
    PrivateVault public immutable vault;
    uint256 public immutable targetDeposit;

    /// @param ethAvailable The holders' ETH after collecting; `ethToDeposit` and `ethSpent` are what this call put to work.
    event Harvested(uint256 ethAvailable, uint256 ethToDeposit, uint256 ethSpent, uint256 tokensDonated);
    event TeamShareAccrued(uint256 amount);
    event TeamPaid(address indexed recipient, uint256 amount);
    event TeamRecipientChanged(address indexed previousRecipient, address indexed newRecipient);
    event CallerTipped(address indexed caller, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event SuccessorProposed(address indexed successor, uint256 readyAt);
    event SuccessorCancelled(address indexed successor);
    event FeeRecipientHandedOver(address indexed successor);

    error EthTransferFailed();
    error NotOwner();
    error NoSuccessor();
    error SuccessorNotReady(uint256 readyAt);
    error NotAPonsLaunch();
    error NotAnEthPair();

    struct Config {
        IPoolManager poolManager;
        IPonsFactory ponsFactory;
        IPonsFeeEscrow feeEscrow;
        IEntryPoint entryPoint;
        PrivateVault vault;
        uint256 targetDeposit;
    }

    /// @param token ZERO, a Pons launch paired with ETH.
    /// @param owner_ Who may change the team's recipient and propose a successor (zero for none).
    /// @param teamRecipient_ Who receives the team's half (zero to let it accrue until one is set).
    constructor(Config memory config, address token, address owner_, address teamRecipient_)
        PonsSwapper(config.poolManager, config.ponsFactory)
    {
        PonsLaunchedToken memory launch = config.ponsFactory.getLaunchedToken(token);
        if (!launch.exists || launch.token != token) revert NotAPonsLaunch();
        if (launch.pairToken != address(0)) revert NotAnEthPair();

        feeEscrow = config.feeEscrow;
        entryPoint = config.entryPoint;
        vault = config.vault;
        targetDeposit = config.targetDeposit;
        _setMarket(token);
        owner = owner_;
        teamRecipient = teamRecipient_;
        emit OwnershipTransferred(address(0), owner_);
        emit TeamRecipientChanged(address(0), teamRecipient_);
    }

    // ------------------------------------------------------------------
    // Owner
    // ------------------------------------------------------------------

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @notice Sets who receives the team's half from now on, and pays it what is owed.
    function setTeamRecipient(address newRecipient) external onlyOwner nonReentrant {
        emit TeamRecipientChanged(teamRecipient, newRecipient);
        teamRecipient = newRecipient;
        _payTeam();
    }

    /// @notice Proposes `successor` as ZERO's next creator fee recipient; anyone can carry it out after the delay.
    function proposeSuccessor(address successor) external onlyOwner {
        if (successor == address(0)) revert NoSuccessor();
        pendingSuccessor = successor;
        successorReadyAt = block.timestamp + SUCCESSOR_DELAY;
        emit SuccessorProposed(successor, successorReadyAt);
    }

    function cancelSuccessor() external onlyOwner {
        address successor = pendingSuccessor;
        if (successor == address(0)) revert NoSuccessor();
        delete pendingSuccessor;
        delete successorReadyAt;
        emit SuccessorCancelled(successor);
    }

    /// @notice Makes the proposed successor ZERO's creator fee recipient on Pons, once the delay has passed. Anyone
    ///         may call it. Fees already credited to this contract stay claimable here by `harvest`.
    function executeSuccessor() external {
        address successor = pendingSuccessor;
        if (successor == address(0)) revert NoSuccessor();
        if (block.timestamp < successorReadyAt) revert SuccessorNotReady(successorReadyAt);
        delete pendingSuccessor;
        delete successorReadyAt;
        IPonsFactoryRecipient(address(ponsFactory)).transferCreatorFeeRecipient(address(zero), successor);
        emit FeeRecipientHandedOver(successor);
    }

    /// @notice Hands ownership on; `address(0)` renounces it, and then the team's recipient and the fee recipient can
    ///         never change again.
    function transferOwnership(address newOwner) external onlyOwner {
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    // ------------------------------------------------------------------
    // Harvest
    // ------------------------------------------------------------------

    /// @notice Collects the creator fees, pays the team its half, and turns the other half into gas and holder yield.
    ///         Anyone may call it.
    function harvest() external nonReentrant returns (uint256 tokensDonated) {
        uint256 gasStart = gasleft();
        uint256 before = address(this).balance;
        _collect();
        uint256 collected = address(this).balance - before;
        if (collected != 0) {
            uint256 share = collected * TEAM_SHARE_BPS / BPS;
            teamOwed += share;
            emit TeamShareAccrued(share);
        }
        uint256 available = address(this).balance - teamOwed;
        vault.poke();
        vault.absorb();

        // At most this much is put to work; the rest covers the caller's refund, known only at the end.
        uint256 eth = available * (BPS - CALLER_TIP_BPS) / BPS;

        // 1. The gas deposit, with ETH first.
        uint256 toDeposit;
        uint256 deposit = entryPoint.balanceOf(address(vault));
        if (deposit < targetDeposit && eth != 0) {
            toDeposit = targetDeposit - deposit < eth ? targetDeposit - deposit : eth;
            entryPoint.depositTo{value: toDeposit}(address(vault));
            eth -= toDeposit;
        }

        // 2. One small buy of ZERO for the vault per L1 block; what does not fit stays here for the next harvest.
        uint256 spent;
        uint256 ema = vault.tokensPerEthEma();
        if (eth != 0 && ema != 0 && block.number != lastBuyBlock) {
            (uint256 spend, uint256 minOut) = _fitBuy(eth, ema);
            if (spend != 0) {
                lastBuyBlock = block.number;
                tokensDonated = _buy(spend, minOut);
                _donate(tokensDonated);
                spent = spend;
                vault.poke();
            }
        }

        emit Harvested(available, toDeposit, spent, tokensDonated);

        // The caller's refund: the gas of this call at no more than twice the base fee, only if it put ETH to work, and at
        // most 0.5% of that work (so it fits in the part set aside above).
        uint256 worked = toDeposit + spent;
        if (worked != 0) {
            uint256 price = tx.gasprice < 2 * block.basefee ? tx.gasprice : 2 * block.basefee;
            uint256 tip = (gasStart - gasleft() + GAS_OVERHEAD) * price;
            uint256 cap = worked * CALLER_TIP_BPS / (BPS - CALLER_TIP_BPS);
            if (tip > cap) tip = cap;
            if (tip != 0) {
                (bool ok,) = msg.sender.call{value: tip}("");
                if (!ok) revert EthTransferFailed();
                emit CallerTipped(msg.sender, tip);
            }
        }

        _payTeam();
    }

    /// @notice Pays the team what it is owed. Anyone may call it; `harvest` does it too.
    function payTeam() external nonReentrant {
        _payTeam();
    }

    /// @notice ETH the next harvest would have for the holders, not counting fees Pons has yet to sweep.
    function claimable() external view returns (uint256) {
        uint256 escrowed = feeEscrow.balanceOf(address(this));
        return escrowed - escrowed * TEAM_SHARE_BPS / BPS + address(this).balance - teamOwed;
    }

    /// @dev Never reverts: a recipient that refuses the ETH leaves it owed.
    function _payTeam() private {
        uint256 amount = teamOwed;
        address recipient = teamRecipient;
        if (amount == 0 || recipient == address(0)) return;
        teamOwed = 0;
        (bool ok,) = recipient.call{value: amount}("");
        if (ok) emit TeamPaid(recipient, amount);
        else teamOwed = amount;
    }

    /// @dev Moves the fees Pons holds for ZERO into the escrow, then claims them. Each step may have nothing to do
    ///      (or need the Pons sweep operator, when fees still sit in ZERO), so none of them may block the harvest.
    function _collect() private {
        if (_settleGraduation()) {
            try IPonsHook(address(_poolKey.hooks)).sweepPoolFees(PoolId.unwrap(poolId()), 0, 0) {} catch {}
        } else {
            try curve.sweepFees(0) {} catch {}
        }
        if (feeEscrow.balanceOf(address(this)) != 0) feeEscrow.claim();
    }

    /// @dev The largest buy, from what the market's depth allows down by halvings, that moves the price by no more
    ///      than MAX_IMPACT_BPS (on average it then fills about half that far from the spot price) and pays no more than
    ///      MAX_PREMIUM_BPS above the average, after fees. Returns its size and minimum out, or zeros.
    function _fitBuy(uint256 eth, uint256 ema) private returns (uint256 spend, uint256 minOut) {
        uint256 spot = spotPrice();
        if (spot == 0) return (0, 0);
        spend = eth;
        uint256 cap = _impactCap();
        if (cap != 0 && spend > cap) spend = cap;
        for (uint256 i; i < MAX_HALVINGS && spend != 0; ++i) {
            uint256 nearSpot = _expectedTokens(spend, spot) * (BPS - MAX_IMPACT_BPS / 2) / BPS;
            uint256 nearAverage = _expectedTokens(spend, ema) * (BPS - MAX_PREMIUM_BPS) / BPS;
            minOut = nearSpot > nearAverage ? nearSpot : nearAverage;
            if (minOut != 0 && _quote(spend) >= minOut) return (spend, minOut);
            spend /= 2;
        }
        return (0, 0);
    }

    /// @dev ETH that moves the price by about MAX_IMPACT_BPS: on the pool, from its active liquidity; on the curve, from
    ///      its ETH reserve. Both move the price by about twice the share of the ETH side a buy adds.
    function _impactCap() private view returns (uint256) {
        if (onPool()) {
            PoolId id = poolId();
            (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(id);
            uint128 liquidity = poolManager.getLiquidity(id);
            if (sqrtPriceX96 == 0 || liquidity == 0) return 0;
            uint256 ethSide = FullMath.mulDiv(liquidity, 1 << 96, sqrtPriceX96);
            return ethSide * MAX_IMPACT_BPS / (2 * BPS);
        }
        (uint256 quoteReserve,) = curve.getReserves();
        return quoteReserve * MAX_IMPACT_BPS / (2 * BPS);
    }

    function _quote(uint256 ethIn) private returns (uint256) {
        return onPool() ? _quotePool(true, ethIn) : _quoteCurve(true, ethIn, address(this));
    }

    /// @dev ZERO that `eth` buys at `tokensPerEth`, after the Pons fees.
    function _expectedTokens(uint256 eth, uint256 tokensPerEth) private view returns (uint256) {
        return FullMath.mulDiv(eth, tokensPerEth * (BPS - _feeBps()), 1e18 * BPS);
    }

    /// @dev The Pons fees on a trade: the same rates on the curve and on the graduated pool.
    function _feeBps() private view returns (uint256) {
        return curve.feeBps() + curve.creatorTaxBps();
    }

    function _donate(uint256 amount) private {
        zero.forceApprove(address(vault), amount);
        vault.donate(amount);
    }
}
