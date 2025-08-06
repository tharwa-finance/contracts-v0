// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
/*
▗▄▄▄▖▗▖ ▗▖ ▗▄▖ ▗▄▄▖ ▗▖ ▗▖ ▗▄▖ 
  █  ▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌
  █  ▐▛▀▜▌▐▛▀▜▌▐▛▀▚▖▐▌ ▐▌▐▛▀▜▌
  █  ▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▙█▟▌▐▌ ▐▌


visit : https://tharwa.finance                         
*/

/* ─── OpenZeppelin ─────────────────────────────────────────────────────────── */
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/* ─── TharwaBondVaultV1 ────────────────────────────────────────────────────── */
/// @title TharwaBondVaultV1
/// @notice ERC1155 vault that issues fixed-term discounted bonds redeemable in THUSD
/// @dev Bond token IDs equal their maturity timestamp truncated to UTC midnight
contract TharwaBondVaultV1 is
    ERC1155Supply,
    AccessControl,
    Pausable,
    ReentrancyGuard
{
    /// -----------------------------------------------------------------------
    /// Custom errors
    /// -----------------------------------------------------------------------
    error ZeroAmount();
    error BelowMinimumFaceAmount();
    error CapExceeded();
    error BondMatured();
    error BondNotMatured();
    error InvalidPrice();
    error MaturityCollision();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------
    event BondIssued(
        address indexed user,
        uint256 tokenId,
        uint256 amount,
        uint256 price,
        uint256 maturity
    );
    event BondRedeemed(
        address indexed user,
        uint256 indexed tokenId,
        uint256 indexed redeemAmount
    );
    event BondEarlyExit(
        address indexed user,
        uint256 indexed tokenId,
        uint256 exitAmount,
        uint256 actualExitAmount
    );
    event BondPriceUpdated(
        BondDuration indexed duration,
        uint256 indexed newPrice
    );
    event BondCapUpdated(BondDuration indexed duration, uint256 indexed newCap);

    /// ----------------------------------------------------------------------
    /// Configuration
    /// ----------------------------------------------------------------------
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    string public constant name = "Tharwa THUSD Bond";
    string public constant symbol = "ThBond";

    /// Minimum face amount to purchase (10 THUSD)
    uint256 public constant MIN_FACE_AMOUNT = 10e18;
    uint256 public constant EARLY_EXIT_PENALTY_RATE_PER_DAY = 0.002e18; // 0.2 %
    uint256 public constant MAX_EARLY_EXIT_PENALTY_RATE = 0.2e18; // 20 %

    /// Stablecoin used for payment and redemption
    IERC20 public immutable THUSD;

    enum BondDuration {
        NinetyDays,
        OneEightyDays,
        ThreeSixtyDays
    }

    struct BondSeries {
        uint256 price; // discounted price (e.g. 0.95 THUSD)
        uint256 duration; // seconds
        uint256 cap; // max face value
        uint256 outstanding; // live liability
    }

    mapping(BondDuration => BondSeries) public bondSeries;
    mapping(uint256 => BondDuration) public maturitySeries; // maturity → duration
    mapping(address => EnumerableSet.UintSet) private _userOwnedBonds; // user → bond tokens

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------
    constructor(
        address thusd_,
        uint256 initialCap
    ) ERC1155("https://bondmeta.tharwa.finance/v1/bond/{id}.json") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        THUSD = IERC20(thusd_);

        // For 4% APY at 90 days
        bondSeries[BondDuration.NinetyDays] = BondSeries({
            price: 990375751614897437, // 0.9903757516148974e18
            duration: 90 days,
            cap: initialCap,
            outstanding: 0
        });

        // For 6% APY at 180 days
        bondSeries[BondDuration.OneEightyDays] = BondSeries({
            price: 971673581959479060, // 0.9716735819594791e18
            duration: 180 days,
            cap: initialCap,
            outstanding: 0
        });

        // For 8% APY at 360 days
        bondSeries[BondDuration.ThreeSixtyDays] = BondSeries({
            price: 926902608116467852, // 0.9269026081164679e18
            duration: 360 days,
            cap: initialCap,
            outstanding: 0
        });
    }

    /* ====================================================================== */
    /*  User Ops                                                          */
    /* ====================================================================== */

    /// @notice Purchase fixed-term bond tokens
    /// @param duration Selected bond duration enum value
    /// @param faceAmount Face value amount (in THUSD) to buy
    /// @dev Transfers discounted THUSD from buyer, mints ERC1155 token whose id is maturity timestamp, and records series data. Emits {BondIssued}. Reverts with {ZeroAmount} or {CapExceeded} or {MaturityCollision}.
    function purchaseBond(
        BondDuration duration,
        uint256 faceAmount
    ) external whenNotPaused nonReentrant {
        if (faceAmount == 0) revert ZeroAmount();
        if (faceAmount < MIN_FACE_AMOUNT) revert BelowMinimumFaceAmount();
        BondSeries storage series = bondSeries[duration];
        if (series.outstanding + faceAmount > series.cap) revert CapExceeded();

        uint256 cost = (faceAmount * series.price) / 1e18;
        uint256 maturity = _midnightUTC(block.timestamp + series.duration);

        if (maturitySeries[maturity] != duration) {
            if (totalSupply(maturity) > 0) {
                revert MaturityCollision();
            } else {
                maturitySeries[maturity] = duration; // set maturity series if not already set
            }
        }

        _mint(msg.sender, maturity, faceAmount, "");
        _userOwnedBonds[msg.sender].add(maturity);
        series.outstanding += faceAmount;

        THUSD.safeTransferFrom(msg.sender, address(this), cost);
        emit BondIssued(
            msg.sender,
            maturity,
            faceAmount,
            series.price,
            maturity
        );
    }

    /// @notice Exit a bond position before maturity applying a penalty
    /// @param tokenId Bond token ID (its maturity timestamp)
    /// @param faceAmount Face value amount to exit
    /// @return payout Amount of THUSD returned after penalty
    /// @dev Burns bond tokens and transfers THUSD minus early-exit penalty. Emits {BondEarlyExit}. Reverts with {BondMatured}.
    function earlyExit(
        uint256 tokenId,
        uint256 faceAmount
    ) external whenNotPaused returns (uint256 payout) {
        if (block.timestamp >= tokenId) revert BondMatured();

        // burns checks balance
        _burn(msg.sender, tokenId, faceAmount);
        if (balanceOf(msg.sender, tokenId) == 0) {
            _userOwnedBonds[msg.sender].remove(tokenId);
        }
        BondDuration duration = maturitySeries[tokenId];
        bondSeries[duration].outstanding -= faceAmount;

        uint256 daysLeft = (tokenId - block.timestamp) / 1 days + 1;
        uint256 pen = daysLeft * EARLY_EXIT_PENALTY_RATE_PER_DAY;
        if (pen > MAX_EARLY_EXIT_PENALTY_RATE) {
            pen = MAX_EARLY_EXIT_PENALTY_RATE;
        }

        payout = (faceAmount * (1e18 - pen)) / 1e18;
        THUSD.safeTransfer(msg.sender, payout);
        emit BondEarlyExit(msg.sender, tokenId, faceAmount, payout);
    }

    /// @notice Redeem matured bond tokens for their full face value
    /// @param tokenId Bond token ID (its maturity timestamp)
    /// @dev Burns tokens and transfers THUSD 1:1. Emits {BondRedeemed}. Reverts with {BondNotMatured} if called before maturity.
    function redeemBond(uint256 tokenId) external whenNotPaused {
        if (block.timestamp < tokenId) revert BondNotMatured();
        uint256 bal = balanceOf(msg.sender, tokenId);

        _burn(msg.sender, tokenId, bal);
        _userOwnedBonds[msg.sender].remove(tokenId);
        BondDuration duration = maturitySeries[tokenId];
        bondSeries[duration].outstanding -= bal;

        THUSD.safeTransfer(msg.sender, bal);
        emit BondRedeemed(msg.sender, tokenId, bal);
    }

    /// @notice Returns the total outstanding liabilities for all bond series
    function totalOutstanding() public view returns (uint256) {
        return
            bondSeries[BondDuration.NinetyDays].outstanding +
            bondSeries[BondDuration.OneEightyDays].outstanding +
            bondSeries[BondDuration.ThreeSixtyDays].outstanding;
    }

    /// @notice Returns all bond token IDs owned by a user
    function getBondsForUser(
        address user
    ) external view returns (uint256[] memory) {
        return _userOwnedBonds[user].values();
    }

    /* ====================================================================== */
    /*  Admin Ops                                                             */
    /* ====================================================================== */
    /// @notice Update discounted issue price for a bond duration
    /// @param d Bond duration enum
    /// @param newPrice New discounted price scaled by 1e18. Must be < 1e18
    /// @dev onlyRole(DEFAULT_ADMIN_ROLE). Emits {BondPriceUpdated}. Reverts with {InvalidPrice}.
    function setBondPrice(
        BondDuration d,
        uint256 newPrice
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newPrice >= 1e18) revert InvalidPrice();
        bondSeries[d].price = newPrice;
        emit BondPriceUpdated(d, newPrice);
    }

    /// @notice Update issuance cap for a bond duration
    /// @param d Bond duration enum
    /// @param newCap New cap expressed in face value units
    /// @dev onlyRole(DEFAULT_ADMIN_ROLE). Emits {BondCapUpdated}.
    function setBondCap(
        BondDuration d,
        uint256 newCap
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bondSeries[d].cap = newCap;
        emit BondCapUpdated(d, newCap);
    }

    function setURI(
        string calldata newuri
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(newuri);
    }

    function rescueTokens(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).safeTransfer(to, amount);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /* ---------------------------------------------------------------------- */
    function _midnightUTC(uint256 timestamp) internal pure returns (uint256) {
        return (timestamp / 1 days) * 1 days;
    }

    // ----------------------------------------------------------------------
    /// @dev Required override for multiple inheritance (ERC1155 & AccessControl)
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
