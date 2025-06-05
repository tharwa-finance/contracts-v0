// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/*
▗▄▄▄▖▗▖ ▗▖ ▗▄▖ ▗▄▄▖ ▗▖ ▗▖ ▗▄▖ 
  █  ▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌
  █  ▐▛▀▜▌▐▛▀▜▌▐▛▀▚▖▐▌ ▐▌▐▛▀▜▌
  █  ▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▙█▟▌▐▌ ▐▌


visit : https://tharwa.finance                         
*/

/**
 * @title thUSDSwap
 * @dev A contract that allows users to swap between stablecoins (DAI, USDC, USDT) and thUSD at a 1:1 value ratio.
 * Handles decimal differences between tokens (6-decimal USDC/USDT and 18-decimal DAI/thUSD).
 * Stable coins are sent to treasury for future liquidity and RWA investments.
 * @notice This contract is non-custodial and requires users to approve token transfers before swapping.
 */
contract thUSDSwap is Ownable, ReentrancyGuard {
    /// @notice Address of the DAI token contract (18 decimals)
    address public immutable dai;

    /// @notice Address of the USDC token contract (6 decimals)
    address public immutable usdc;

    /// @notice Address of the USDT token contract (6 decimals)
    address public immutable usdt;

    /// @notice Address of the thUSD token contract (18 decimals)
    address public immutable thUSD;

    /// @notice Address of the treasury
    address public immutable treasury;

    using SafeERC20 for IERC20;

    /**
     * @dev Scaling factor to convert between 6-decimal and 18-decimal tokens
     * 10^12 = 10^(18-6) for converting between 6-decimal and 18-decimal tokens
     */
    uint256 private constant SCALING_FACTOR = 1e12;

    /* errors */
    /// @notice Error thrown when a zero amount is provided for a swap
    error AmountZero();

    /// @notice Error thrown when there's not enough thUSD liquidity to fulfill a swap
    error InsufficientLiquidity();

    /* events */
    /**
     * @notice Emitted when USDC is swapped for thUSD
     * @param user The address that initiated the swap
     * @param usdcAmount The amount of USDC swapped (6 decimals)
     * @param thUSDAmount The amount of thUSD received (18 decimals)
     */
    event SwapUSDCForThUSD(
        address indexed user,
        uint256 usdcAmount,
        uint256 thUSDAmount
    );

    /**
     * @notice Emitted when DAI is swapped for thUSD
     * @param user The address that initiated the swap
     * @param daiAmount The amount of DAI swapped (18 decimals)
     * @param thUSDAmount The amount of thUSD received (18 decimals)
     */
    event SwapDAIForThUSD(
        address indexed user,
        uint256 daiAmount,
        uint256 thUSDAmount
    );

    /**
     * @notice Emitted when USDT is swapped for thUSD
     * @param user The address that initiated the swap
     * @param usdtAmount The amount of USDT swapped (6 decimals)
     * @param thUSDAmount The amount of thUSD received (18 decimals)
     */
    event SwapUSDTForThUSD(
        address indexed user,
        uint256 usdtAmount,
        uint256 thUSDAmount
    );

    /**
     * @notice Emitted when thUSD is moved to treasury
     */
    event ThUSDMovedToTreasury(uint256 amount);

    /**
     * @notice Constructor that initializes the contract with token addresses
     * @param _dai Address of the DAI token contract
     * @param _usdc Address of the USDC token contract
     * @param _usdt Address of the USDT token contract
     * @param _thUSD Address of the thUSD token contract
     * @param _treasury Address of the treasury
     */
    constructor(
        address _dai,
        address _usdc,
        address _usdt,
        address _thUSD,
        address _treasury
    ) Ownable(msg.sender) {
        dai = _dai;
        usdc = _usdc;
        usdt = _usdt;
        thUSD = _thUSD;
        treasury = _treasury;
    }

    /**
     * @notice Swap USDC (6 decimals) for thUSD (18 decimals) at a 1:1 value.
     * @param usdcAmount Amount of USDC to swap (units with 6‑decimals)
     */
    function swapUSDC(uint256 usdcAmount) external nonReentrant {
        if (usdcAmount == 0) {
            revert AmountZero();
        }
        // Ensure the contract has enough thUSD liquidity
        uint256 thAmount = usdcAmount * SCALING_FACTOR;
        if (IERC20(thUSD).balanceOf(address(this)) < thAmount) {
            revert InsufficientLiquidity();
        }

        // Pull USDC from the caller safely
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), usdcAmount);

        // Transfer thUSD to the caller
        IERC20(thUSD).safeTransfer(msg.sender, thAmount);

        // send the stablecoin to the treasury
        IERC20(usdc).safeTransfer(treasury, usdcAmount);

        emit SwapUSDCForThUSD(msg.sender, usdcAmount, thAmount);
    }

    /**
     * @notice Swap USDT (6 decimals) for thUSD (18 decimals) at a 1:1 value.
     * @param usdtAmount Amount of USDT to swap (units with 6‑decimals)
     */
    function swapUSDT(uint256 usdtAmount) external nonReentrant {
        if (usdtAmount == 0) {
            revert AmountZero();
        }

        // USDT is also 6 decimals so we need to scale it up by 12
        uint256 thAmount = usdtAmount * SCALING_FACTOR;
        if (IERC20(thUSD).balanceOf(address(this)) < thAmount) {
            revert InsufficientLiquidity();
        }

        IERC20(usdt).safeTransferFrom(msg.sender, address(this), usdtAmount);
        IERC20(thUSD).safeTransfer(msg.sender, thAmount);
        IERC20(usdt).safeTransfer(treasury, usdtAmount);

        emit SwapUSDTForThUSD(msg.sender, usdtAmount, thAmount);
    }

    /**
     * @notice Swap DAI (18 decimals) for thUSD (18 decimals) at a 1:1 value.
     * @param daiAmount Amount of DAI to swap (units with 18‑decimals)
     */
    function swapDAI(uint256 daiAmount) external nonReentrant {
        if (daiAmount == 0) {
            revert AmountZero();
        }

        // no scaling needed
        uint256 thAmount = daiAmount;
        if (IERC20(thUSD).balanceOf(address(this)) < thAmount) {
            revert InsufficientLiquidity();
        }

        IERC20(dai).safeTransferFrom(msg.sender, address(this), daiAmount);
        IERC20(thUSD).safeTransfer(msg.sender, thAmount);
        IERC20(dai).safeTransfer(treasury, daiAmount);

        emit SwapDAIForThUSD(msg.sender, daiAmount, thAmount);
    }

    /**
     * @notice Returns the current thUSD balance of the contract
     * @return The amount of thUSD tokens held by the contract
     */
    function getThUSD() external view returns (uint256) {
        return IERC20(thUSD).balanceOf(address(this));
    }

    /** admin ops */

    /**
     * withdraw thUSD used for excess liquidity for accounting purposes
     */
    function MoveThUSDToTreasury(uint256 amount) external onlyOwner {
        IERC20(thUSD).safeTransfer(treasury, amount);
        emit ThUSDMovedToTreasury(amount);
    }

    /**
     * @notice Allows the owner to rescue ETH sent to the contract by mistake
     * @dev Only callable by the contract owner
     */
    function rescueETH() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    /**
     * rescue ERC20 tokens sent to the contract by mistake
     */
    function rescueERC20(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    /**
     * @dev Fallback function to receive ETH
     */
    receive() external payable {}
}
