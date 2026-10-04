// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";

import {IOpaquePool} from "./interfaces/IOpaquePool.sol";
import {IPonsFactory, IPonsCurve, IPonsHook, IPonsFeeEscrow, PonsLaunchedToken} from "./pons/IPons.sol";

/// @title OpaqueHarvester
/// @notice $OPA's Pons creator fee recipient. Anyone can call `harvest`, which collects the creator fees Pons holds
///         for $OPA (in ETH), owes the team its share, and spends the rest on $OPA that it donates to the pool, so
///         every shielded holder's shares are worth more.
///
///         The holders' ETH buys in small steps: at most one buy per block, each sized to move the price by no more
///         than 0.5%, and never more than 15% dearer than the harvester's own price average. A buy that small is not
///         worth sandwiching: pushing the price up before it and selling after costs the Pons fees on both legs for
///         at most the 0.5% it moves the price. What does not fit waits here for the next harvest.
///
///         The caller is refunded the gas of a call that put ETH to work, at no more than twice the base fee and
///         never more than 0.5% of that work, so calling it in a loop earns nothing.
///
///         The owner can change the team's recipient, propose a successor (public, executable by anyone after
///         `SUCCESSOR_DELAY`), cancel it, hand ownership on, or renounce it. There is no other way to move the
///         Pons fee recipient away from this contract. Pons can still redirect it through its own takeover process.
///
///         Draft. Unaudited. The Pons calls are written from documentation and have not run against the live
///         contracts.
contract OpaqueHarvester {
    using StateLibrary for IPoolManager;

    // ---------------------------------------------------------------- constants

    uint256 public constant MAX_IMPACT_BPS = 50;
    uint256 public constant MAX_PREMIUM_BPS = 1_500;
    uint256 public constant CALLER_TIP_BPS = 50;
    uint256 public constant GAS_OVERHEAD = 25_000;
    uint256 public constant SUCCESSOR_DELAY = 24 hours;
    /// @dev A block's price enters the average clamped to this distance from it, with weight 1/8.
    uint256 public constant MAX_PRICE_STEP_BPS = 1_000;
    uint256 private constant BPS = 10_000;
    uint256 private constant MAX_HALVINGS = 8;

    // ---------------------------------------------------------------- immutables

    IPoolManager public immutable poolManager;
    IPonsFactory public immutable ponsFactory;
    IPonsFeeEscrow public immutable feeEscrow;
    IOpaquePool public immutable pool;
    address public immutable token;
    IPonsCurve public immutable curve;
    /// @notice The team's share of the ETH each harvest collects, in basis points. Fixed at deployment.
    uint256 public immutable teamShareBps;

    // pool key of the graduated Pons pool: native ETH / token
    Currency private immutable _currency1;
    uint24 private immutable _poolFee;
    int24 private immutable _tickSpacing;
    IHooks private immutable _hooks;

    // ---------------------------------------------------------------- state

    address public owner;
    address public teamRecipient;
    uint256 public teamOwed;
    address public pendingSuccessor;
    uint256 public successorReadyAt;
    uint256 public lastBuyBlock;

    /// @notice Moving average of the price, tokens per ETH scaled by 1e18. Zero before the first price.
    uint256 public tokensPerEthEma;
    uint256 public lastSpot;
    uint256 public lastPriceBlock;

    uint256 private _lock = 1;

    // ---------------------------------------------------------------- events and errors

    event Harvested(uint256 ethAvailable, uint256 ethSpent, uint256 tokensDonated);
    event BuySkipped(uint256 ethTried);
    event TeamShareAccrued(uint256 amount);
    event TeamPaid(address indexed recipient, uint256 amount);
    event TeamRecipientChanged(address indexed previousRecipient, address indexed newRecipient);
    event CallerTipped(address indexed caller, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event SuccessorProposed(address indexed successor, uint256 readyAt);
    event SuccessorCancelled(address indexed successor);
    event FeeRecipientHandedOver(address indexed successor);
    event PriceUpdated(uint256 tokensPerEthEma);

    error Reentrancy();
    error EthTransferFailed();
    error TokenTransferFailed();
    error NotOwner();
    error NoSuccessor();
    error SuccessorNotReady(uint256 readyAt);
    error NotAPonsLaunch();
    error NotAnEthPair();
    error BadTeamShare();
    error NotPoolManager();
    error NotSelf();
    error InsufficientOutput();
    error BadSwap();

    modifier nonReentrant() {
        if (_lock != 1) revert Reentrancy();
        _lock = 2;
        _;
        _lock = 1;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    struct Config {
        IPoolManager poolManager;
        IPonsFactory ponsFactory;
        IPonsFeeEscrow feeEscrow;
        IOpaquePool pool; // receives the donations, must already exist
    }

    /// @param token_ $OPA, a Pons launch paired with native ETH.
    /// @param owner_ May change the team's recipient and propose a successor (zero for none).
    /// @param teamRecipient_ Receives the team's share (zero lets it accrue until one is set).
    /// @param teamShareBps_ Team share of collected ETH, at most 10,000.
    constructor(Config memory config, address token_, address owner_, address teamRecipient_, uint256 teamShareBps_) {
        if (teamShareBps_ > BPS) revert BadTeamShare();
        PonsLaunchedToken memory launch = config.ponsFactory.getLaunchedToken(token_);
        if (!launch.exists || launch.token != token_) revert NotAPonsLaunch();
        if (launch.pairToken != address(0)) revert NotAnEthPair();

        poolManager = config.poolManager;
        ponsFactory = config.ponsFactory;
        feeEscrow = config.feeEscrow;
        pool = config.pool;
        token = token_;
        curve = IPonsCurve(launch.curve);
        teamShareBps = teamShareBps_;
        _currency1 = Currency.wrap(token_);
        _poolFee = launch.poolFee;
        _tickSpacing = launch.tickSpacing;
        _hooks = IHooks(config.ponsFactory.memeHook());

        owner = owner_;
        teamRecipient = teamRecipient_;
        emit OwnershipTransferred(address(0), owner_);
        emit TeamRecipientChanged(address(0), teamRecipient_);
    }

    receive() external payable {}

    // ---------------------------------------------------------------- owner

    function setTeamRecipient(address newRecipient) external onlyOwner nonReentrant {
        emit TeamRecipientChanged(teamRecipient, newRecipient);
        teamRecipient = newRecipient;
        _payTeam();
    }

    /// @notice Proposes `successor` as $OPA's next creator fee recipient. Anyone can carry it out after the delay.
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

    /// @notice Makes the proposed successor the creator fee recipient on Pons, once the delay has passed. Anyone
    ///         may call it. Fees already credited to this contract stay claimable here by `harvest`.
    function executeSuccessor() external {
        address successor = pendingSuccessor;
        if (successor == address(0)) revert NoSuccessor();
        if (block.timestamp < successorReadyAt) revert SuccessorNotReady(successorReadyAt);
        delete pendingSuccessor;
        delete successorReadyAt;
        ponsFactory.transferCreatorFeeRecipient(token, successor);
        emit FeeRecipientHandedOver(successor);
    }

    /// @notice `address(0)` renounces ownership: the team's recipient and the fee recipient can then never change.
    function transferOwnership(address newOwner) external onlyOwner {
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    // ---------------------------------------------------------------- harvest

    /// @notice Collects the creator fees, owes the team its share, buys $OPA with the rest and donates it to the
    ///         pool. Anyone may call it.
    function harvest() external nonReentrant returns (uint256 tokensDonated) {
        uint256 gasStart = gasleft();
        uint256 available = _collectAndSplit();
        _poke();

        // At most this much is put to work. The rest covers the caller's refund, known only at the end.
        uint256 spent;
        (spent, tokensDonated) = _buyAndDonate((available * (BPS - CALLER_TIP_BPS)) / BPS);

        emit Harvested(available, spent, tokensDonated);
        if (spent != 0) _tipCaller(gasStart, spent);
        _payTeam();
    }

    /// @dev Collects from Pons, owes the team its share of what arrived, and returns the holders' ETH.
    function _collectAndSplit() private returns (uint256 available) {
        uint256 before = address(this).balance;
        _collect();
        uint256 collected = address(this).balance - before;
        uint256 share = (collected * teamShareBps) / BPS;
        if (share != 0) {
            teamOwed += share;
            emit TeamShareAccrued(share);
        }
        available = address(this).balance - teamOwed;
    }

    /// @dev One small buy per block, donated to the pool. What does not fit waits for the next harvest.
    function _buyAndDonate(uint256 eth) private returns (uint256 spent, uint256 donated) {
        uint256 ema = tokensPerEthEma;
        if (eth == 0 || ema == 0 || block.number == lastBuyBlock) return (0, 0);
        (spent, donated) = _buyFitted(eth, ema);
        if (spent == 0) {
            emit BuySkipped(eth);
            return (0, 0);
        }
        lastBuyBlock = block.number;
        _donate(donated);
        _poke();
    }

    /// @dev Refunds the caller the gas of a call that put ETH to work, at no more than twice the base fee and no
    ///      more than 0.5% of that work.
    function _tipCaller(uint256 gasStart, uint256 spent) private {
        uint256 price = tx.gasprice < 2 * block.basefee ? tx.gasprice : 2 * block.basefee;
        uint256 tip = (gasStart - gasleft() + GAS_OVERHEAD) * price;
        uint256 cap = (spent * CALLER_TIP_BPS) / (BPS - CALLER_TIP_BPS);
        if (tip > cap) tip = cap;
        if (tip == 0) return;
        (bool ok,) = msg.sender.call{value: tip}("");
        if (!ok) revert EthTransferFailed();
        emit CallerTipped(msg.sender, tip);
    }

    /// @notice Pays the team what it is owed. Anyone may call it. Never reverts on a recipient that refuses ETH.
    function payTeam() external nonReentrant {
        _payTeam();
    }

    /// @notice ETH the next harvest would have for the holders, not counting fees Pons has yet to sweep.
    function claimable() external view returns (uint256) {
        uint256 escrowed = feeEscrow.balanceOf(address(this));
        return escrowed - (escrowed * teamShareBps) / BPS + address(this).balance - teamOwed;
    }

    function _payTeam() private {
        uint256 amount = teamOwed;
        address recipient = teamRecipient;
        if (amount == 0 || recipient == address(0)) return;
        teamOwed = 0;
        (bool ok,) = recipient.call{value: amount}("");
        if (ok) emit TeamPaid(recipient, amount);
        else teamOwed = amount;
    }

    /// @dev Each step may have nothing to do, or may need Pons' sweep operator, so none of them may block a harvest.
    function _collect() private {
        PonsLaunchedToken memory launch = ponsFactory.getLaunchedToken(token);
        if (launch.phase == 2) {
            // a call to a non-contract reverts before `try` can catch it, so check the hook exists first
            if (address(_hooks).code.length != 0) {
                try IPonsHook(address(_hooks)).sweepPoolFees(PoolId.unwrap(_poolId()), 0, 0) {} catch {}
            }
        } else if (launch.phase == 0) {
            try curve.sweepFees(0) {} catch {}
        }
        if (feeEscrow.balanceOf(address(this)) != 0) feeEscrow.claim();
    }

    // ---------------------------------------------------------------- price

    function _poolKey() private view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: _currency1,
            fee: _poolFee,
            tickSpacing: _tickSpacing,
            hooks: _hooks
        });
    }

    function _poolId() private view returns (PoolId) {
        return PoolIdLibrary.toId(_poolKey());
    }

    /// @dev 0 when no venue is live: neither the curve (before it is ready to graduate) nor the graduated pool.
    function _venue() private view returns (uint8 v) {
        PonsLaunchedToken memory launch = ponsFactory.getLaunchedToken(token);
        if (launch.phase == 2) return 2;
        if (launch.phase == 0 && !curve.readyToGraduate()) return 1;
        return 0;
    }

    /// @notice Tokens per ETH at the live venue, 1e18 scale, or 0 when none is live.
    function spotPrice() public view returns (uint256) {
        uint8 v = _venue();
        if (v == 2) {
            (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(_poolId());
            if (sqrtPriceX96 == 0) return 0;
            uint256 x = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 64); // price * 2^128
            return FullMath.mulDiv(x, 1e18, 1 << 128);
        }
        if (v == 1) {
            (uint256 quoteReserve, uint256 tokenReserve) = curve.getReserves();
            if (quoteReserve == 0) return 0;
            return (tokenReserve * 1e18) / quoteReserve;
        }
        return 0;
    }

    /// @dev The first update in a block folds the previous update's price into the average, clamped to
    ///      +-MAX_PRICE_STEP_BPS of it, with weight 1/8. The first price ever seeds the average.
    function _poke() private {
        uint256 spot = spotPrice();
        if (spot == 0) return;
        uint256 ema = tokensPerEthEma;
        if (ema == 0) {
            tokensPerEthEma = spot;
            lastSpot = spot;
            lastPriceBlock = block.number;
            emit PriceUpdated(spot);
            return;
        }
        if (block.number != lastPriceBlock) {
            uint256 close = lastSpot;
            uint256 hi = (ema * (BPS + MAX_PRICE_STEP_BPS)) / BPS;
            uint256 lo = (ema * (BPS - MAX_PRICE_STEP_BPS)) / BPS;
            if (close > hi) close = hi;
            if (close < lo) close = lo;
            ema = (ema * 7 + close) / 8;
            tokensPerEthEma = ema;
            emit PriceUpdated(ema);
        }
        lastSpot = spot;
        lastPriceBlock = block.number;
    }

    // ---------------------------------------------------------------- buying

    /// @dev Tries the largest buy the market's depth allows, halving until the venue fills it within the bounds.
    ///      Returns the ETH spent and the tokens received, or zeros.
    function _buyFitted(uint256 eth, uint256 ema) private returns (uint256 spend, uint256 got) {
        uint256 spot = spotPrice();
        if (spot == 0) return (0, 0);
        spend = eth;
        uint256 cap = _impactCap();
        if (cap != 0 && spend > cap) spend = cap;
        for (uint256 i; i < MAX_HALVINGS && spend != 0; ++i) {
            uint256 nearSpot = (_expectedTokens(spend, spot) * (BPS - MAX_IMPACT_BPS / 2)) / BPS;
            uint256 nearAverage = (_expectedTokens(spend, ema) * (BPS - MAX_PREMIUM_BPS)) / BPS;
            uint256 minOut = nearSpot > nearAverage ? nearSpot : nearAverage;
            if (minOut != 0) {
                try this.buyStep(spend, minOut) returns (uint256 out) {
                    if (out >= minOut) return (spend, out);
                } catch {}
            }
            spend /= 2;
        }
        return (0, 0);
    }

    /// @notice Internal: performs one buy. Only this contract can call it, so a failed attempt reverts cleanly.
    function buyStep(uint256 spend, uint256 minOut) external returns (uint256 got) {
        if (msg.sender != address(this)) revert NotSelf();
        uint256 balBefore = _tokenBalance();
        uint8 v = _venue();
        if (v == 2) {
            poolManager.unlock(abi.encode(spend, minOut));
        } else if (v == 1) {
            curve.buy{value: spend}(spend, minOut, address(this));
        } else {
            revert BadSwap();
        }
        got = _tokenBalance() - balBefore;
        if (got < minOut) revert InsufficientOutput();
    }

    /// @dev Uniswap v4 callback for the graduated pool buy: ETH in, tokens out, exact input, no price limit.
    ///      `minOut` is the only price protection.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        (uint256 spend, uint256 minOut) = abi.decode(data, (uint256, uint256));
        return abi.encode(_swapIn(spend, minOut));
    }

    function _swapIn(uint256 spend, uint256 minOut) private returns (uint256 out) {
        PoolKey memory key = _poolKey();
        BalanceDelta d = poolManager.swap(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(spend),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            ""
        );
        if (BalanceDeltaLibrary.amount0(d) > 0 || BalanceDeltaLibrary.amount1(d) <= 0) revert BadSwap();
        out = uint256(uint128(BalanceDeltaLibrary.amount1(d)));
        if (out < minOut) revert InsufficientOutput();
        poolManager.settle{value: uint256(uint128(-BalanceDeltaLibrary.amount0(d)))}();
        poolManager.take(key.currency1, address(this), out);
    }

    /// @dev ETH that moves the price by about MAX_IMPACT_BPS: on the pool from its active liquidity, on the curve
    ///      from its ETH reserve. Both move the price by about twice the share of the ETH side a buy adds.
    function _impactCap() private view returns (uint256) {
        uint8 v = _venue();
        if (v == 2) {
            PoolId id = _poolId();
            (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(id);
            uint128 liquidity = poolManager.getLiquidity(id);
            if (sqrtPriceX96 == 0 || liquidity == 0) return 0;
            uint256 ethSide = FullMath.mulDiv(liquidity, 1 << 96, sqrtPriceX96);
            return (ethSide * MAX_IMPACT_BPS) / (2 * BPS);
        }
        (uint256 quoteReserve,) = curve.getReserves();
        return (quoteReserve * MAX_IMPACT_BPS) / (2 * BPS);
    }

    /// @dev Tokens that `eth` buys at `tokensPerEth`, after the Pons fees.
    function _expectedTokens(uint256 eth, uint256 tokensPerEth) private view returns (uint256) {
        return FullMath.mulDiv(eth, tokensPerEth * (BPS - _feeBps()), 1e18 * BPS);
    }

    /// @dev The Pons fees on a trade: the same rates on the curve and on the graduated pool.
    function _feeBps() private view returns (uint256) {
        return curve.feeBps() + curve.creatorTaxBps();
    }

    // ---------------------------------------------------------------- token plumbing

    function _donate(uint256 amount) private {
        _approve(address(pool), amount);
        pool.donate(amount);
    }

    function _approve(address spender, uint256 amount) private {
        (bool ok, bytes memory ret) =
            token.call(abi.encodeWithSignature("approve(address,uint256)", spender, amount));
        if (!ok || (ret.length != 0 && !abi.decode(ret, (bool)))) revert TokenTransferFailed();
    }

    function _tokenBalance() private view returns (uint256) {
        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSignature("balanceOf(address)", address(this)));
        if (!ok || ret.length < 32) revert TokenTransferFailed();
        return abi.decode(ret, (uint256));
    }
}
