// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TharwaDistributorWithVesting} from "src/TharwaDistributorWithVesting.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {TharwaDistributorWithVestingBase} from "./withVesting.base.t.sol";

contract DistributorWithVesting_Claims is TharwaDistributorWithVestingBase {
    function setUp() public override {
        super.setUp();
    }

    /// @notice test that claim before start timestamp does nothing
    function test_claim_beforeStart_doesNothing() public {
        uint256 start = block.timestamp + 100;
        uint256 end = block.timestamp + 200;

        _campaignCreated(start, end);
        _vestedDepositSingleUser(user1, 1000 ether);

        uint256 balanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        distributor.claim(CAMPAIGN_1);
        uint256 balanceAfter = token.balanceOf(user1);

        assertEq(balanceAfter, balanceBefore);
    }

    /// @notice test that claim after end timestamp transfers the full amount to the user
    function test_claim_afterEnd_transfersFullAmount() public {
        uint256 start = block.timestamp + 100;
        uint256 end = block.timestamp + 200;
        _campaignCreated(start, end);
        _vestedDepositSingleUser(user1, 1000 ether);

        vm.warp(end + 1);

        uint256 balanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        distributor.claim(CAMPAIGN_1);
        uint256 balanceAfter = token.balanceOf(user1);

        assertEq(balanceAfter - balanceBefore, 1000 ether);
    }

    /// @notice test that claim when 1/3 of the vesting duration has passed transfers 1/3 of the total amount to the user
    function test_claim_oneThirdTime_transfersOneThirdAmount() public {
        uint256 start = block.timestamp + 100;
        uint256 end = block.timestamp + 400; // 300 second duration

        _campaignCreated(start, end);
        _vestedDepositSingleUser(user1, 3000 ether);

        vm.warp(start + 100); // 1/3 of the way through

        uint256 balanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        distributor.claim(CAMPAIGN_1);
        uint256 balanceAfter = token.balanceOf(user1);

        assertEq(balanceAfter - balanceBefore, 1000 ether);
    }

    /// @notice test that claiming twice in the same block (once getClaimableAmount > 0) doesn't transfer anything the second time
    function test_claim_twiceInSameBlock_secondTransfersNothing() public {
        uint256 start = block.timestamp + 100;
        uint256 end = block.timestamp + 200;

        _campaignCreated(start, end);
        _vestedDepositSingleUser(user1, 1000 ether);

        vm.warp(end + 1);

        vm.startPrank(user1);
        distributor.claim(CAMPAIGN_1);

        uint256 balanceBefore = token.balanceOf(user1);
        distributor.claim(CAMPAIGN_1);
        uint256 balanceAfter = token.balanceOf(user1);
        vm.stopPrank();

        assertEq(balanceAfter, balanceBefore);
    }

    /// @notice test that claiming for an account without a vesting schedule does nothing
    function test_claim_noVestingSchedule_doesNothing() public {
        _campaignCreated(block.timestamp + 100, block.timestamp + 200);

        uint256 balanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        distributor.claim(CAMPAIGN_1);
        uint256 balanceAfter = token.balanceOf(user1);

        assertEq(balanceAfter, balanceBefore);
    }

    /// @notice test that claiming when getClaimableAmount > 0, increases the balance of the caller
    function test_claim_withClaimableAmount_increasesCallerBalance() public {
        uint256 start = block.timestamp + 100;
        uint256 end = block.timestamp + 200;

        _campaignCreated(start, end);
        _vestedDepositSingleUser(user1, 1000 ether);

        vm.warp(end + 1);

        uint256 balanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        distributor.claim(CAMPAIGN_1);
        uint256 balanceAfter = token.balanceOf(user1);

        assertGt(balanceAfter, balanceBefore);
    }

    /// @notice test that claiming when getClaimableAmount > 0, decreases the claimable amount
    function test_claim_withClaimableAmount_decreasesClaimableAmount() public {
        uint256 start = block.timestamp + 100;
        uint256 end = block.timestamp + 200;

        _campaignCreated(start, end);
        _vestedDepositSingleUser(user1, 1000 ether);

        vm.warp(end + 1);

        uint256 claimableBefore = distributor.getClaimableAmount(CAMPAIGN_1, user1);
        vm.prank(user1);
        distributor.claim(CAMPAIGN_1);
        uint256 claimableAfter = distributor.getClaimableAmount(CAMPAIGN_1, user1);

        assertLt(claimableAfter, claimableBefore);
        assertEq(claimableAfter, 0);
    }

    /// @notice test that claiming when getClaimableAmount > 0, decreases the balance of the contract
    function test_claim_withClaimableAmount_decreasesContractBalance() public {
        uint256 start = block.timestamp + 100;
        uint256 end = block.timestamp + 200;

        _campaignCreated(start, end);
        _vestedDepositSingleUser(user1, 1000 ether);

        vm.warp(end + 1);

        uint256 contractBalanceBefore = token.balanceOf(address(distributor));
        vm.prank(user1);
        distributor.claim(CAMPAIGN_1);
        uint256 contractBalanceAfter = token.balanceOf(address(distributor));

        assertLt(contractBalanceAfter, contractBalanceBefore);
        assertEq(contractBalanceBefore - contractBalanceAfter, 1000 ether);
    }

    /// @notice test that claiming when getClaimableAmount > 0, increases the claimed amount
    function test_claim_withClaimableAmount_increasesClaimedAmount() public {
        uint256 start = block.timestamp + 100;
        uint256 end = block.timestamp + 200;

        _campaignCreated(start, end);
        _vestedDepositSingleUser(user1, 1000 ether);

        vm.warp(end + 1);

        uint256 claimedBefore = distributor.getClaimedAmount(CAMPAIGN_1, user1);
        vm.prank(user1);
        distributor.claim(CAMPAIGN_1);
        uint256 claimedAfter = distributor.getClaimedAmount(CAMPAIGN_1, user1);

        assertGt(claimedAfter, claimedBefore);
        assertEq(claimedAfter, 1000 ether);
    }

    /// @notice test that claiming multiple times over the duration in the end yields the total vested amount
    function test_claim_multipleTimes_overDuration_yieldsTotalVested() public {
        uint256 start = block.timestamp + 100;
        uint256 end = block.timestamp + 400; // 300 second duration

        uint256 totalVested = 5555 ether;
        _campaignCreated(start, end);
        _vestedDepositSingleUser(user1, totalVested);

        uint256 balanceBefore = token.balanceOf(user1);

        vm.warp(start + 100); // 1/3 of the way through
        vm.prank(user1);
        distributor.claim(CAMPAIGN_1);

        vm.warp(start + 200); // 2/3 of the way through
        vm.prank(user1);
        distributor.claim(CAMPAIGN_1);

        vm.warp(end + 1); // after end
        vm.prank(user1);
        distributor.claim(CAMPAIGN_1);
        uint256 balanceAfter = token.balanceOf(user1);

        assertEq(balanceAfter - balanceBefore, totalVested);
    }
}
