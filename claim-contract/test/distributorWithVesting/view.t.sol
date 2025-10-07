// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TharwaDistributorWithVesting} from "src/TharwaDistributorWithVesting.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {TharwaDistributorWithVestingBase} from "./withVesting.base.t.sol";

contract DistributorWithVesting_Views is TharwaDistributorWithVestingBase {
    function setUp() public override {
        super.setUp();
    }

    ////////////////////////// tests /////////////////////////////

    /// @notice test that getClaimableAmount returns 0 before start timestamp
    function test_getClaimableAmount_beforeStart_returnsZero() public {
        _campaignCreated(block.timestamp + 100, block.timestamp + 200);
        _vestedDepositSingleUser(user1, 1000 ether);

        // Before start time
        assertEq(distributor.getClaimableAmount(CAMPAIGN_1, user1), 0);
    }

    /// @notice test that getClaimableAmount returns the full amount after end timestamp
    function test_getClaimableAmount_afterEnd_returnsFullAmount() public {
        _campaignCreated(block.timestamp + 100, block.timestamp + 200);
        _vestedDepositSingleUser(user1, 1000 ether);

        // After end time
        vm.warp(block.timestamp + 201);
        assertEq(distributor.getClaimableAmount(CAMPAIGN_1, user1), 1000 ether);
    }

    /// @notice test that getClaimableAmount returns the full amount after end timestamp, when setVestingSchedules is called twice for the same account
    function test_getClaimableAmount_afterEnd_withDoubleDeposit_returnsFullAmount() public {
        _campaignCreated(block.timestamp + 100, block.timestamp + 200);
        _vestedDepositSingleUser(user1, 1000 ether);

        // Second deposit
        _vestedDepositSingleUser(user1, 1000 ether);

        // After end time
        vm.warp(endTime + 1);
        assertEq(distributor.getClaimableAmount(CAMPAIGN_1, user1), 2000 ether);
    }

    /// @notice test that getClaimableAmount returns 1/3 of the total amount when 1/3 of the time has passed
    function test_getClaimableAmount_oneThirdTime_returnsOneThirdAmount() public {
        uint256 start = block.timestamp + 100;
        uint256 end = block.timestamp + 400; // 300 second duration

        _campaignCreated(start, end);
        _vestedDepositSingleUser(user1, 3000 ether);

        // 1/3 of the way through (100 seconds into 300 second duration)
        vm.warp(start + 100);
        assertEq(distributor.getClaimableAmount(CAMPAIGN_1, user1), 1000 ether);
    }

    /// @notice test that getAmountAtTheEndOfCampaign returns the total amount before start timestamp and after end timestamp
    function test_getAmountAtTheEndOfCampaign_returnsCorrectAmount() public {
        uint256 start = block.timestamp + 100;
        uint256 end = block.timestamp + 200;

        _campaignCreated(start, end);
        _vestedDepositSingleUser(user1, 1000 ether);

        // Before start time
        assertEq(distributor.getAmountAtTheEndOfCampaign(CAMPAIGN_1, user1), 1000 ether);

        // After end time
        vm.warp(end + 1);
        assertEq(distributor.getAmountAtTheEndOfCampaign(CAMPAIGN_1, user1), 1000 ether);
    }
}
