// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
▗▄▄▄▖▗▖ ▗▖ ▗▄▖ ▗▄▄▖ ▗▖ ▗▖ ▗▄▖ 
  █  ▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌
  █  ▐▛▀▜▌▐▛▀▜▌▐▛▀▚▖▐▌ ▐▌▐▛▀▜▌
  █  ▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▙█▟▌▐▌ ▐▌


visit : https://tharwa.finance                         
*/

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";

/**
 * @dev Interface for UniswapV2Factory to create trading pairs
 */
interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

/**
 * @dev Interface for UniswapV2Router02 to interact with the DEX
 */
interface IUniswapV2Router02 {
    function factory() external view returns (address);

    function WETH() external view returns (address);

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
}

/**
 * @title TRWA
 * @author Tharwa Finance
 * @notice LayerZero OFT (Omnichain Fungible Token) with launch-phase trading guards and configurable buy/sell taxes
 * @dev Extends LayerZero's OFT for cross-chain functionality and OpenZeppelin's Ownable for access control
 */
contract TRWA is Ownable, OFT {
    /* ─────────────── launch settings ─────────────── */

    /// Maximum token supply (10 billion tokens)
    uint256 public constant MAX_SUPPLY = 10_000_000_000 * 1e18;

    /// Maximum tax in basis points (10%)
    uint256 public constant MAX_TAX_BPS = 1_000;

    /// Tax calculation denominator (100% = 10,000 basis points)
    uint256 internal constant TAX_DENOMINATOR = 10_000;

    /// Treasury address that receives collected taxes
    address public treasury;

    /// Trading enabled flag - gates trading functionality
    bool public tradingOpen;

    /// Uniswap V2 pair address (set once via setPair)
    address public pair;

    /// Mapping of addresses exempt from taxes
    mapping(address => bool) public isFeeExempt;

    /// Buy tax in basis points (default 0%)
    uint16 public buyTaxBps = 0;

    /// Sell tax in basis points (default 0%)
    uint16 public sellTaxBps = 0;

    // errors
    /// Thrown when attempting to set tax above maximum allowed
    /// @param maxTaxBps Maximum allowed tax in basis points
    /// @param actualTaxBps Attempted tax value in basis points
    error MaxTaxBpsExceeded(uint256 maxTaxBps, uint256 actualTaxBps);
    /// @notice Thrown when providing zero address where not allowed
    error ZeroAddress();
    /// @notice Thrown when attempting to open trading when already open
    error TradingAlreadyOpen();

    /* ─────────────── constructor ─────────────── */

    /**
     * @notice Initializes the TRWA token contract
     * @dev Mints 70% of supply to contract for liquidity, 30% to treasury (reserved for airdrops, marketing, CEX listing, etc.)
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param lzEndpoint_ LayerZero endpoint address for cross-chain functionality
     * @param delegate_ Initial owner and OFT delegate address
     * @param treasury_ Treasury address to receive taxes and initial allocation
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address lzEndpoint_,
        address delegate_,
        address treasury_
    ) OFT(name_, symbol_, lzEndpoint_, delegate_) Ownable(delegate_) {
        // self-mint 70% to the inital lp
        _mint(address(this), (MAX_SUPPLY * 70) / 100);
        // rest to treasury
        _mint(treasury_, (MAX_SUPPLY * 30) / 100);

        treasury = treasury_;
    }

    /* ─────────────── core fee / guard logic ─────────────── */

    /**
     * @notice Internal transfer function with tax logic
     * @dev Overrides OpenZeppelin's _update to implement taxes on buys/sells
     * @dev Applies taxes only on non-exempt addresses during trades with the pair
     * @param from Sender address
     * @param to Recipient address
     * @param amount Transfer amount
     */
    function _update(address from, address to, uint256 amount) internal override {
        // Apply launch‑phase checks only for normal transfers (not mint/burn) and non‑exempt wallets.
        if (from != address(0) && to != address(0) && !isFeeExempt[from] && !isFeeExempt[to]) {
            bool isBuy = from == pair;
            bool isSell = to == pair;

            // Calculate and collect fee
            uint256 fee = ((isBuy ? buyTaxBps : isSell ? sellTaxBps : 0) * amount) / TAX_DENOMINATOR;
            if (fee > 0) {
                super._update(from, treasury, fee);
                amount -= fee;
            }
        }

        // Final transfer
        super._update(from, to, amount);
    }

    /** admin ops **/

    /**
     * @notice Opens trading and creates Uniswap V2 liquidity pool
     * @dev Can only be called once. Uses the ETH sent to create initial liquidity
     * @dev Approves router, creates pair, adds liquidity, and enables trading
     */
    function openTrading() external payable onlyOwner {
        // setup router address
        address uniswapV2Router_ = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

        // check if trading is already open
        if (tradingOpen) {
            revert TradingAlreadyOpen();
        }

        // create the uniswap pair and add liquidity

        IUniswapV2Router02 uniswapV2Router = IUniswapV2Router02(uniswapV2Router_);

        _approve(address(this), uniswapV2Router_, balanceOf(address(this)));

        address tokenPair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
            address(this),
            uniswapV2Router.WETH()
        );

        uniswapV2Router.addLiquidityETH{ value: msg.value }(
            address(this),
            balanceOf(address(this)),
            0,
            0,
            msg.sender,
            block.timestamp
        );

        tradingOpen = true;
        setPair(tokenPair);
    }

    /**
     * @notice Updates buy and sell tax rates
     * @dev Both values must not exceed MAX_TAX_BPS
     * @param buyBps New buy tax in basis points
     * @param sellBps New sell tax in basis points
     */
    function setTaxes(uint16 buyBps, uint16 sellBps) external onlyOwner {
        if (buyBps > MAX_TAX_BPS) {
            revert MaxTaxBpsExceeded(MAX_TAX_BPS, buyBps);
        }
        if (sellBps > MAX_TAX_BPS) {
            revert MaxTaxBpsExceeded(MAX_TAX_BPS, sellBps);
        }
        buyTaxBps = buyBps;
        sellTaxBps = sellBps;
    }

    /**
     * @notice Sets or removes fee exemption for an address
     * @param account Address to update fee exemption status
     * @param flag True to exempt from fees, false to remove exemption
     */
    function setFeeExempt(address account, bool flag) external onlyOwner {
        isFeeExempt[account] = flag;
    }

    /**
     * @notice Sets the Uniswap pair address for tax calculations
     * @dev Can be called by owner to update the pair address
     * @param _pair Address of the Uniswap V2 pair
     */
    function setPair(address _pair) public onlyOwner {
        if (_pair == address(0)) {
            revert ZeroAddress();
        }

        pair = _pair;
    }
}
