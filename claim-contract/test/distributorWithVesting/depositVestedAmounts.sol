// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TharwaDistributorWithVesting} from "src/TharwaDistributorWithVesting.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {TharwaDistributorWithVestingBase} from "./withVesting.base.t.sol";

contract DistributorWithVesting_Deposits is TharwaDistributorWithVestingBase {
    function setUp() public override {
        super.setUp();
    }

    function _craft2Schedules(uint256 amountUser1, uint256 amountUser2)
        internal
        view
        returns (TharwaDistributorWithVesting.VestingSchedule[] memory)
    {
        TharwaDistributorWithVesting.VestingSchedule[] memory schedules =
            new TharwaDistributorWithVesting.VestingSchedule[](2);
        schedules[0] = TharwaDistributorWithVesting.VestingSchedule(user1, amountUser1);
        schedules[1] = TharwaDistributorWithVesting.VestingSchedule(user2, amountUser2);
        return schedules;
    }

    /// @notice test that when VestingSchedules are set, the total amount of tokens is pulled from the caller
    function test_depositVestedAmounts_pullsTokensFromCaller() public {
        _campaignCreated(block.timestamp + 100, block.timestamp + 200);

        TharwaDistributorWithVesting.VestingSchedule[] memory schedules = _craft2Schedules(1000 ether, 2000 ether);

        uint256 adminBalanceBefore = token.balanceOf(admin);
        vm.prank(admin);
        distributor.depositVestedAmounts(CAMPAIGN_1, schedules);
        uint256 adminBalanceAfter = token.balanceOf(admin);

        assertEq(adminBalanceBefore - adminBalanceAfter, 3000 ether);
    }

    /// @notice test that when VestingSchedules are set, the total amount of tokens is received by the distributor contract
    function test_depositVestedAmounts_transfersTokensToDistributor() public {
        vm.prank(admin);
        distributor.createCampaign(CAMPAIGN_1, address(token), block.timestamp + 100, block.timestamp + 200);

        TharwaDistributorWithVesting.VestingSchedule[] memory schedules = _craft2Schedules(1000 ether, 2000 ether);

        uint256 distributorBalanceBefore = token.balanceOf(address(distributor));
        vm.prank(admin);
        distributor.depositVestedAmounts(CAMPAIGN_1, schedules);
        uint256 distributorBalanceAfter = token.balanceOf(address(distributor));

        assertEq(distributorBalanceAfter - distributorBalanceBefore, 3000 ether);
    }

    /// @notice test that when VestingSchedules are set on existing schedules, the total tokens are pulled by the caller and received by the distributor
    function test_depositVestedAmounts_onExistingSchedules_pullsAndReceivesTokens() public {
        _campaignCreated(block.timestamp + 100, block.timestamp + 200);

        // First deposit
        TharwaDistributorWithVesting.VestingSchedule[] memory schedules1 = _craft2Schedules(1000 ether, 2000 ether);

        vm.prank(admin);
        distributor.depositVestedAmounts(CAMPAIGN_1, schedules1);

        // Second deposit to existing schedules
        uint256 adminBalanceBefore = token.balanceOf(admin);
        uint256 distributorBalanceBefore = token.balanceOf(address(distributor));

        TharwaDistributorWithVesting.VestingSchedule[] memory schedules2 = _craft2Schedules(500 ether, 500 ether);
        vm.prank(admin);
        distributor.depositVestedAmounts(CAMPAIGN_1, schedules2);

        uint256 adminBalanceAfter = token.balanceOf(admin);
        uint256 distributorBalanceAfter = token.balanceOf(address(distributor));

        assertEq(
            adminBalanceBefore - adminBalanceAfter, 1000 ether, "The second deposit should pull 1000 tokens from admin"
        );
        assertEq(
            distributorBalanceAfter - distributorBalanceBefore,
            1000 ether,
            "The second deposit should transfer 1000 tokens to the distributor"
        );
    }

    /// @notice test that when VestingSchedules are set on an existing schedule, the total amount at the end of the period is updated accordingly
    function test_depositVestedAmounts_onExistingSchedule_updatesVestingAmount() public {
        _campaignCreated(block.timestamp + 100, block.timestamp + 200);

        // First deposit
        TharwaDistributorWithVesting.VestingSchedule[] memory schedules1 = _craft2Schedules(1000 ether, 2000 ether);
        vm.prank(admin);
        distributor.depositVestedAmounts(CAMPAIGN_1, schedules1);
        assertEq(distributor.getAmountAtTheEndOfCampaign(CAMPAIGN_1, user1), 1000 ether);

        // Second deposit to existing schedule
        TharwaDistributorWithVesting.VestingSchedule[] memory schedules2 = _craft2Schedules(1000 ether, 2000 ether);
        vm.prank(admin);
        distributor.depositVestedAmounts(CAMPAIGN_1, schedules2);

        assertEq(distributor.getAmountAtTheEndOfCampaign(CAMPAIGN_1, user1), 2000 ether);
    }

    /// @notice test that when setVestingSchedules is called on a non-existing campaign, it reverts with the correct error
    function test_depositVestedAmounts_nonExistingCampaign_reverts() public {
        TharwaDistributorWithVesting.VestingSchedule[] memory schedules = _craft2Schedules(1000 ether, 2000 ether);

        vm.expectRevert(abi.encodeWithSignature("CampaignDoesNotExist()"));
        vm.prank(admin);
        distributor.depositVestedAmounts(999, schedules);
    }

    /// @notice test that when setVestingSchedules is called on a finished campaign, it reverts with the correct error
    function test_depositVestedAmounts_finishedCampaign_reverts() public {
        vm.prank(admin);
        distributor.createCampaign(CAMPAIGN_1, address(token), block.timestamp + 100, block.timestamp + 200);

        // Move time to after campaign end
        vm.warp(block.timestamp + 300);

        TharwaDistributorWithVesting.VestingSchedule[] memory schedules = _craft2Schedules(1000 ether, 2000 ether);

        vm.expectRevert(abi.encodeWithSignature("CampaignAlreadyFinished()"));
        vm.prank(admin);
        distributor.depositVestedAmounts(CAMPAIGN_1, schedules);
    }
}
