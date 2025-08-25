// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
▗▄▄▄▖▗▖ ▗▖ ▗▄▖ ▗▄▄▖ ▗▖ ▗▖ ▗▄▖ 
  █  ▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌
  █  ▐▛▀▜▌▐▛▀▜▌▐▛▀▚▖▐▌ ▐▌▐▛▀▜▌
  █  ▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▙█▟▌▐▌ ▐▌

visit : https://tharwa.finance
*/

/* ─── OpenZeppelin v5 ─────────────────────────────────────────────────────── */
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ThUSDSilo} from "./ThUSDSilo.sol";

/* ─── Tharwa Staked Version ──────────────────────────────────────────────── */
/// @title sThUSD
/// @notice Tharwa Staked USD (sThUSD) ERC‑4626 vault for staking thUSD.
/// @dev fees, cooldown, vesting, and donation-attack resistant accounting.
contract sThUSD is ERC4626, AccessControl, Pausable, ERC20Permit {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /* -------------------------------- Errors ------------------------------- */
    error AmountZero();
    error NoShares();
    error VestingActive();
    error PeriodZero();
    error CooldownNotAllowed();
    error FeeTooHigh();
    error RecipientZero();
    error ReceiverBlacklisted();
    error CooldownActive();
    error Blacklisted();
    error NoSurplus();
    error ExceedsSurplus();
    error InvalidCooldown();
    error CooldownIsOff();
    error InvalidAmount();

    /* ------------------------------- Roles -------------------------------- */
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant YIELD_MANAGER_ROLE = keccak256("YIELD_MANAGER_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    /* ---------------------------- Constants ------------------------------ */
    uint256 private constant _BPS = 10_000; // basis-point scale

    /* ----------------------- Accounting (donations) ----------------------- */
    // Tracks the assets that are actually attributed to share-holders.
    // Do NOT rely on raw token balanceOf(vault) to avoid donation/inflation tricks.
    uint256 private _pooledAssets;

    // Linear vesting of newly added yield
    uint256 public vestingPeriod = 30 days;
    uint256 private _vestingAmount;
    uint256 private _lastDistributionTime;

    // --- Cooldown / Claim Silo ---
    // If cooldownPeriod == 0: standard ERC4626 withdrawals/redeems are enabled; cooldown paths are disabled.
    // If cooldownPeriod  > 0: ERC4626 withdrawals/redeems are disabled; users must use cooldownAssets/cooldownShares
    // to move underlying to the silo, then call unstake(receiver) after cooldown to claim.
    uint256 public cooldownPeriod = 0; // 0, 3 days, or 7 days

    event CooldownPeriodSet(uint256 newPeriod);

    // together they make 256 bits so it can be stored in a single storage slot
    struct UserCooldown {
        uint104 cooldownEnd; // unlock timestamp
        uint152 underlyingAmount; // accumulated underlying to claim
    }

    mapping(address => UserCooldown) public cooldowns;

    ThUSDSilo public immutable silo;

    /* ------------------------------- Fees -------------------------------- */
    uint16 public entryFeeBps; // 0..1000 (<=10%)
    uint16 public exitFeeBps; // 0..1000 (<=10%)
    address public treasury; // where fees are sent

    /* ----------------------------- Controls ------------------------------ */
    mapping(address => bool) private _blacklist; // compliance guard

    /* ------------------------------- Events ------------------------------ */
    event YieldAdded(uint256 amount);
    event VestingPeriodSet(uint256 newPeriod);
    event FeesSet(uint16 entryFeeBps, uint16 exitFeeBps, address treasury);
    event BlacklistSet(address indexed account, bool blacklisted);

    /* ----------------------------- Constructor --------------------------- */
    /// @param thUSD_ The thUSD stable token
    /// @param admin_ Address granted DEFAULT_ADMIN_ROLE and initial manager roles.
    constructor(IERC20 thUSD_, address admin_)
        ERC20("Staked Tharwa USD", "sThUSD")
        ERC4626(thUSD_)
        ERC20Permit("Staked Tharwa USD")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);
        _grantRole(YIELD_MANAGER_ROLE, admin_);
        _grantRole(FEE_MANAGER_ROLE, admin_);
        silo = new ThUSDSilo(address(this), address(thUSD_));
    }

    /* ====================================================================== */
    /*  User Ops                                                              */
    /* ====================================================================== */

    /* -------------------------- Donation Mitigation ---------------------- */
    /// @inheritdoc ERC4626
    function totalAssets() public view override returns (uint256) {
        uint256 unvested = _unvestedAmount();
        return _pooledAssets - unvested;
    }

    function _unvestedAmount() internal view returns (uint256) {
        if (_vestingAmount == 0) return 0;
        uint256 elapsed = block.timestamp - _lastDistributionTime;
        if (elapsed >= vestingPeriod) return 0;
        uint256 remaining = vestingPeriod - elapsed;
        return _vestingAmount.mulDiv(remaining, vestingPeriod, Math.Rounding.Floor);
    }

    /// @dev Resolve ERC20 multiple inheritance (ERC4626 & ERC20Permit both inherit ERC20).
    function decimals() public view override(ERC20, ERC4626) returns (uint8) {
        return super.decimals();
    }

    /* ------------------------- Cooldown / Claim -------------------------- */
    /// @notice Redeem assets and start cooldown to claim converted underlying.
    /// @dev Only available when cooldown is ON (>0). Moves underlying to the silo.
    function cooldownAssets(uint256 assets) external whenNotPaused returns (uint256 shares) {
        if (cooldownPeriod == 0) revert CooldownIsOff(); // operation disabled when cooldown is off
        if (assets == 0) revert AmountZero();
        // Precompute required shares (accounts for exit fee) and guard against oversize requests
        shares = previewWithdraw(assets);
        if (shares > maxRedeem(msg.sender)) revert InvalidAmount();

        UserCooldown storage u = cooldowns[msg.sender];
        u.cooldownEnd = uint104(block.timestamp + cooldownPeriod);
        u.underlyingAmount += uint152(assets);

        _withdraw(msg.sender, address(silo), msg.sender, assets, shares);
    }

    /// @notice Redeem shares and start cooldown to claim converted underlying.
    /// @dev Only available when cooldown is ON (>0). Moves underlying to the silo.
    function cooldownShares(uint256 shares) external whenNotPaused returns (uint256 assets) {
        if (cooldownPeriod == 0) revert CooldownIsOff();
        if (shares == 0) revert AmountZero();
        if (shares > maxRedeem(msg.sender)) revert InvalidAmount();

        assets = previewRedeem(shares);

        UserCooldown storage u = cooldowns[msg.sender];
        u.cooldownEnd = uint104(block.timestamp + cooldownPeriod);
        u.underlyingAmount += uint152(assets);

        _withdraw(msg.sender, address(silo), msg.sender, assets, shares);
    }

    /// @notice Claim the accumulated underlying after cooldown has finished.
    /// @dev If cooldown is OFF (0), allows claiming any previously cooled amount without waiting.
    function unstake(address receiver) external whenNotPaused {
        if (_blacklist[receiver]) revert ReceiverBlacklisted();

        UserCooldown storage u = cooldowns[msg.sender];
        uint256 assets = u.underlyingAmount;
        if (assets == 0) revert AmountZero();

        if (!(block.timestamp >= u.cooldownEnd || cooldownPeriod == 0)) {
            revert InvalidCooldown();
        }

        u.cooldownEnd = 0;
        u.underlyingAmount = 0;

        silo.withdraw(receiver, assets);
    }

    /// @dev Preview taking an entry fee on deposit.
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        uint256 fee = _feeOnTotal(assets, entryFeeBps);
        return super.previewDeposit(assets - fee);
    }

    /// @dev Preview adding an entry fee on mint.
    function previewMint(uint256 shares) public view override returns (uint256) {
        uint256 assets = super.previewMint(shares);
        return assets + _feeOnRaw(assets, entryFeeBps);
    }

    /// @dev Preview adding an exit fee on withdraw.
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        uint256 fee = _feeOnRaw(assets, exitFeeBps);
        return super.previewWithdraw(assets + fee);
    }

    /// @dev Preview taking an exit fee on redeem.
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        uint256 assets = super.previewRedeem(shares);
        return assets - _feeOnTotal(assets, exitFeeBps);
    }

    /// @dev Send entry/exit fee and maintain donation-safe accounting.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        override
        whenNotPaused
    {
        uint256 fee = _feeOnTotal(assets, entryFeeBps);
        super._deposit(caller, receiver, assets, shares);
        if (fee > 0 && treasury != address(0) && treasury != address(this)) {
            IERC20(asset()).safeTransfer(treasury, fee);
        }
        unchecked {
            _pooledAssets += (assets - fee);
        }
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
        whenNotPaused
    {
        if (_blacklist[receiver]) revert ReceiverBlacklisted();
        uint256 fee = _feeOnRaw(assets, exitFeeBps);
        super._withdraw(caller, receiver, owner, assets, shares);
        if (fee > 0 && treasury != address(0) && treasury != address(this)) {
            IERC20(asset()).safeTransfer(treasury, fee);
        }
        unchecked {
            _pooledAssets -= (assets + fee);
        }
    }

    /// @notice ERC4626 withdraw is only available when cooldown is OFF.
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        whenNotPaused
        returns (uint256)
    {
        if (cooldownPeriod > 0) revert CooldownActive();
        return super.withdraw(assets, receiver, owner);
    }

    /// @notice ERC4626 redeem is only available when cooldown is OFF.
    function redeem(uint256 shares, address receiver, address owner) public override whenNotPaused returns (uint256) {
        if (cooldownPeriod > 0) revert CooldownActive();
        return super.redeem(shares, receiver, owner);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20) {
        if (_blacklist[from] || _blacklist[to]) revert Blacklisted();
        super._update(from, to, value);
    }

    /* ----------------------------- FE Views ------------------------------ */
    /// @notice Returns the currently unvested portion of the last added yield.
    function unvestedAmount() external view returns (uint256) {
        return _unvestedAmount();
    }

    /// @notice Returns the vesting start timestamp if a vest is active; otherwise 0.
    function vestingStart() external view returns (uint256) {
        if (_unvestedAmount() == 0) return 0;
        return _lastDistributionTime;
    }

    /// @notice Returns the vesting end timestamp if a vest is active; otherwise 0.
    function vestingEnd() external view returns (uint256) {
        if (_unvestedAmount() == 0) return 0;
        return _lastDistributionTime + vestingPeriod;
    }

    /// @notice Returns the current linear recognition rate (assets/second) while vesting; otherwise 0.
    function currentYieldRatePerSecond() external view returns (uint256) {
        if (_unvestedAmount() == 0) return 0;
        // integer division is fine for display purposes
        return _vestingAmount / vestingPeriod;
    }

    /* ----------------------------- Fee Math ------------------------------ */
    function _feeOnRaw(uint256 assets, uint256 feeBps) private pure returns (uint256) {
        if (feeBps == 0) return 0;
        return assets.mulDiv(feeBps, _BPS, Math.Rounding.Ceil);
    }

    function _feeOnTotal(uint256 assets, uint256 feeBps) private pure returns (uint256) {
        if (feeBps == 0) return 0;
        return assets.mulDiv(feeBps, feeBps + _BPS, Math.Rounding.Ceil);
    }

    /* ====================================================================== */
    /*  Privileged Ops                                                        */
    /* ====================================================================== */

    /* ------------------------------ Yield -------------------------------- */
    /// @notice Push new yield (in underlying) into the vault; linearly vests over `vestingPeriod`.
    /// @dev Requires previous vesting to be finished to keep accounting simple.
    function addYield(uint256 amount) external onlyRole(YIELD_MANAGER_ROLE) whenNotPaused {
        if (amount == 0) revert AmountZero();
        if (totalSupply() == 0) revert NoShares();
        if (_unvestedAmount() != 0) revert VestingActive();

        _vestingAmount = amount;
        _lastDistributionTime = block.timestamp;
        _pooledAssets += amount; // attributed to shareholders, but locked until vested

        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
        emit YieldAdded(amount);
    }

    function setVestingPeriod(uint256 newPeriod) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newPeriod == 0) revert PeriodZero();
        if (_unvestedAmount() != 0) revert VestingActive();
        vestingPeriod = newPeriod;
        emit VestingPeriodSet(newPeriod);
    }

    function setCooldownPeriod(uint256 newPeriod) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // allow: 0 (off), 3 days, or 7 days
        if (!(newPeriod == 0 || newPeriod == 3 days || newPeriod == 7 days)) {
            revert CooldownNotAllowed();
        }
        cooldownPeriod = newPeriod;
        emit CooldownPeriodSet(newPeriod);
    }

    /* ------------------------------ Blacklist ----------------------------- */
    function setBlacklisted(address account, bool blacklisted) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _blacklist[account] = blacklisted;
        emit BlacklistSet(account, blacklisted);
    }

    /* -------------------------------- Fees ------------------------------- */
    function setFees(uint16 entryBps, uint16 exitBps, address recipient) external onlyRole(FEE_MANAGER_ROLE) {
        if (entryBps > 1000 || exitBps > 1000) revert FeeTooHigh(); // caps at 10% each
        if (entryBps > 0 || exitBps > 0) {
            if (recipient == address(0)) revert RecipientZero();
        }
        entryFeeBps = entryBps;
        exitFeeBps = exitBps;
        treasury = recipient;
        emit FeesSet(entryBps, exitBps, recipient);
    }

    /* ------------------------------- Pausing ------------------------------ */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /* ------------------------------ Rescue ------------------------------- */
    /// @notice Recover tokens sent by mistake. Never pulls from accounted assets.
    function rescueERC20(IERC20 token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(token) == asset()) {
            uint256 bal = token.balanceOf(address(this));
            uint256 accounted = _pooledAssets; // includes any still-unvested amount
            if (bal <= accounted) revert NoSurplus();
            if (amount > bal - accounted) revert ExceedsSurplus();
        }
        token.safeTransfer(to, amount);
    }
}
