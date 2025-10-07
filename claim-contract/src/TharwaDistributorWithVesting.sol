// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/*
▗▄▄▄▖▗▖ ▗▖ ▗▄▖ ▗▄▄▖ ▗▖ ▗▖ ▗▄▖ 
  █  ▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌
  █  ▐▛▀▜▌▐▛▀▜▌▐▛▀▚▖▐▌ ▐▌▐▛▀▜▌
  █  ▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▙█▟▌▐▌ ▐▌

visit : https://tharwa.finance
*/

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Multicall} from "lib/openzeppelin-contracts/contracts/utils/Multicall.sol";

/* ─── Custom Errors ─────────────────────────────────────────────────────── */
error InvalidTokenAddress();
error InvalidTimestamps();
error StartTimestampInThePast();
error ExpectedNonZero();
error NoClaimableAmount();
error CampaignAlreadyExists();
error CampaignDoesNotExist();
error CampaignAlreadyFinished();
error FeeOnTransferTokensNotSupported();

/// @title Tharwa Distributor contract with vesting
/// @author @jacopod - github.com/JacoboLansac
/// @notice Vesting contract for distributing ERC20 tokens with linear vesting
contract TharwaDistributorWithVesting is Ownable, Multicall {
    using SafeERC20 for IERC20;

    struct VestingSchedule {
        /// @notice Account to which the vesting schedule applies
        address account;
        /// @notice Amount being vested once the vesting period is over
        uint256 amount;
    }

    struct Campaign {
        /// @notice Token being vested
        address token;
        /// @notice Timestamps for the start of the vesting period
        uint256 startTimestamp;
        /// @notice Timestamps for the end of the vesting period
        uint256 endTimestamp;
    }

    /// @notice Campaigns info
    mapping(uint256 campaignId => Campaign) public campaigns;
    /// @notice Amount being vested per account per campaign
    mapping(uint256 campaignId => mapping(address => uint256)) public vestingAmounts;
    /// @notice Amount already claimed per account per campaign
    mapping(uint256 campaignId => mapping(address => uint256)) public claimedAmounts;

    event CampaignCreated(uint256 campaignId, address token, uint256 startTimestamp, uint256 endTimestamp);
    event VestingSchedulesSet(uint256 campaignId, VestingSchedule[] schedules);
    event Claimed(uint256 campaignId, address indexed account, uint256 amount);

    constructor(address _owner) Ownable(_owner) {}

    //////////////////////////// Admin functions ///////////////////////////

    /// @notice Create a new vesting campaign
    function createCampaign(uint256 campaignId, address token, uint256 startTimestamp, uint256 endTimestamp)
        external
        onlyOwner
    {
        require(token != address(0), InvalidTokenAddress());
        require(startTimestamp < endTimestamp, InvalidTimestamps());
        require(startTimestamp >= block.timestamp, StartTimestampInThePast());
        require(campaigns[campaignId].token == address(0), CampaignAlreadyExists());

        campaigns[campaignId] = Campaign({token: token, startTimestamp: startTimestamp, endTimestamp: endTimestamp});

        emit CampaignCreated(campaignId, token, startTimestamp, endTimestamp);
    }

    /// @notice Set vesting schedules for multiple accounts
    /// @dev This function can be called multiple times to increase the vested amount for a given account
    function depositVestedAmounts(uint256 campaignId, VestingSchedule[] calldata schedules) external onlyOwner {
        Campaign memory campaign = campaigns[campaignId];
        require(campaign.token != address(0), CampaignDoesNotExist());
        require(campaign.endTimestamp > block.timestamp, CampaignAlreadyFinished());

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < schedules.length; i++) {
            VestingSchedule calldata schedule = schedules[i];
            if (schedule.amount == 0) revert ExpectedNonZero();

            // Amounts can be updated. This creates a step-increase in the current claimable.
            vestingAmounts[campaignId][schedule.account] += schedule.amount;
            totalAmount += schedule.amount;
        }

        uint256 balanceBefore = IERC20(campaign.token).balanceOf(address(this));
        IERC20(campaign.token).safeTransferFrom(msg.sender, address(this), totalAmount);
        uint256 balanceAfter = IERC20(campaign.token).balanceOf(address(this));

        require(balanceAfter - balanceBefore == totalAmount, FeeOnTransferTokensNotSupported());

        emit VestingSchedulesSet(campaignId, schedules);
    }

    //////////////////////////// External functions ///////////////////////////

    /// @notice Claim vested tokens for `msg.sender`
    /// @dev intended for normal users
    function claim(uint256 campaignId) external {
        uint256 vestedAmount = _getVestedAmount(campaignId, msg.sender);
        // silently return here if there is nothing vested
        if (vestedAmount == 0) return;

        uint256 claimableAmount = vestedAmount - claimedAmounts[campaignId][msg.sender];
        // silent return if there is nothing to claim
        if (claimableAmount == 0) return;

        // reset the claimable to match what has been vested
        claimedAmounts[campaignId][msg.sender] = vestedAmount;
        IERC20(campaigns[campaignId].token).safeTransfer(msg.sender, claimableAmount);

        emit Claimed(campaignId, msg.sender, claimableAmount);
    }

    ////////////////////////// View functions ///////////////////////////

    function getClaimableAmount(uint256 campaignId, address account) public view returns (uint256) {
        return _getClaimableAmount(campaignId, account);
    }

    function getClaimedAmount(uint256 campaignId, address account) external view returns (uint256) {
        return claimedAmounts[campaignId][account];
    }

    function getAmountAtTheEndOfCampaign(uint256 campaignId, address account) external view returns (uint256) {
        return vestingAmounts[campaignId][account];
    }

    /////////////////////////// Internal functions //////////////////////

    function _getClaimableAmount(uint256 campaignId, address account) internal view returns (uint256) {
        uint256 vestedAmount = _getVestedAmount(campaignId, account);
        uint256 claimed = claimedAmounts[campaignId][account];

        if (vestedAmount <= claimed) {
            return 0;
        }

        return vestedAmount - claimed;
    }

    function _getVestedAmount(uint256 campaignId, address account) internal view returns (uint256) {
        uint256 totalAmount = vestingAmounts[campaignId][account];
        // non existing campaigns will return 0 here
        if (totalAmount == 0) return 0;

        uint256 start = campaigns[campaignId].startTimestamp;
        uint256 end = campaigns[campaignId].endTimestamp;

        if (block.timestamp < start) {
            return 0;
        }

        if (block.timestamp >= end) {
            return totalAmount;
        }

        uint256 vestingDuration = end - start;
        uint256 elapsed = block.timestamp - start;

        return (totalAmount * elapsed) / vestingDuration;
    }
}
