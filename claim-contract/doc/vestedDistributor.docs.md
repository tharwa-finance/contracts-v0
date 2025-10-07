# TharwaDistributorWithVesting

## Purpose

Campaign-oriented contract for distributing ERC20 tokens with linear vesting. Each campaign can have different tokens, start/end timestamps, and vesting schedules. 

- Users can only claim their allocations. No claim-for functionality
- Users can claim multiple campaigns at once thanks to multicall feature
- Users can claim constantly, as rewards are vested linearly on every block
- CampaignIds can be used as "seasons", but also as other extra custom campaigns if needed, as campaigns can run in parallel, with different vesting times, and different tokens. 
- An admin can increase the amount of an ongoing vesting which will step-increase the current claimable amount. If the step jump is not desired, it may be better to just deposit into a new campaign id 

## Admin Usage

### Deployment
```solidity
constructor(address _owner)
```
- `_owner`: Contract owner

### Creating Campaigns
```solidity
createCampaign(uint256 campaignId, address token, uint256 startTimestamp, uint256 endTimestamp)
```
- Only callable by owner
- `campaignId`: Unique identifier for the campaign
- `token`: ERC20 token to distribute for this campaign
- `startTimestamp`: Vesting start time (must be in future)
- `endTimestamp`: Vesting end time (must be after start)
- Each campaign can have different tokens and timeframes

### Setting Vesting Schedules
```solidity
depositVestedAmounts(uint256 campaignId, VestingSchedule[] schedules)
```
- Only callable by owner
- Sets vesting schedules for a specific campaign
- Pulls total token amount from caller
- Can be called multiple times to increase amounts. Note: these increases cause step-jumps in the claimable amounts
- Cannot decrease or delete existing schedules

## User Usage

### Claiming Tokens
```solidity
claim(uint256 campaignId)
```
- Claims all available vested tokens for `msg.sender` from specific campaign
- Silent return if nothing to claim
- Internally calculates linear vesting based on elapsed time

### Multicall Support
The contract inherits from `Multicall`, allowing users to claim from multiple campaigns in a single transaction.

### View Functions
- `getClaimableAmount(uint256 campaignId, address account)`: Current claimable amount for specific campaign
- `getClaimedAmount(uint256 campaignId, address account)`: Total claimed so far for specific campaign
- `getAmountAtTheEndOfCampaign(uint256 campaignId, address account)`: Total vesting amount for specific campaign

## Security Considerations

### Gotchas
- **Cannot delete vestings**: Admins cannot alter campaign start/end times, nor decrease vesting amounts. They can increase them
- **Step increases**: Increasing vesting amounts creates immediate claimable jumps
- **Silent claims**: `claim(campaignId)` returns silently if nothing available (no revert)
