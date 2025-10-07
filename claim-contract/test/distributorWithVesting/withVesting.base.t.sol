// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TharwaDistributorWithVesting} from "src/TharwaDistributorWithVesting.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {MerkleProof} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

contract TharwaDistributorWithVestingBase is Test {
    TharwaDistributorWithVesting public distributor;
    ERC20Mock public token;

    address admin = makeAddr("admin");

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");

    uint256 constant CAMPAIGN_1 = 1;
    uint256 constant CAMPAIGN_2 = 2;

    // Common test timing values
    uint256 public startTime;
    uint256 public endTime;
    uint256 public vestingDuration;

    function setUp() public virtual {
        vm.prank(admin);
        distributor = new TharwaDistributorWithVesting(admin);

        token = new ERC20Mock();

        // Mint tokens to distributor for distribution
        token.mint(address(distributor), 1000000 ether);

        // Set up admin with large token allowance for all tests
        token.mint(admin, 10000000 ether);
        vm.prank(admin);
        token.approve(address(distributor), type(uint256).max);

        // Set default timing values
        startTime = block.timestamp + 100;
        endTime = block.timestamp + 200;
        vestingDuration = endTime - startTime;
    }

    /////////////////// internal handy functions /////////////////
    function _campaignCreated(uint256 start, uint256 end) internal {
        vm.prank(admin);
        distributor.createCampaign(CAMPAIGN_1, address(token), start, end);
    }

    function _vestedDepositSingleUser(address user, uint256 amount) internal {
        TharwaDistributorWithVesting.VestingSchedule[] memory schedules =
            new TharwaDistributorWithVesting.VestingSchedule[](1);
        schedules[0] = TharwaDistributorWithVesting.VestingSchedule(user, amount);

        vm.prank(admin);
        distributor.depositVestedAmounts(CAMPAIGN_1, schedules);
    }

    //////////////////////////////////////////////////////

    function test_initialDeployment() public view {
        assertEq(distributor.owner(), admin);
    }

    // Modifiers for common test setup patterns

    modifier withStandardCampaign() {
        vm.prank(admin);
        distributor.createCampaign(CAMPAIGN_1, address(token), startTime, endTime);
        _;
    }

    modifier withCustomCampaign(uint256 campaignId, uint256 _startTime, uint256 _endTime) {
        vm.prank(admin);
        distributor.createCampaign(campaignId, address(token), _startTime, _endTime);
        _;
    }

    modifier withVestingSchedule(address user, uint256 amount) {
        TharwaDistributorWithVesting.VestingSchedule[] memory schedules =
            new TharwaDistributorWithVesting.VestingSchedule[](1);
        schedules[0] = TharwaDistributorWithVesting.VestingSchedule(user, amount);

        vm.prank(admin);
        distributor.depositVestedAmounts(CAMPAIGN_1, schedules);
        _;
    }

    modifier withMultipleVestingSchedules(uint256 user1Amount, uint256 user2Amount) {
        TharwaDistributorWithVesting.VestingSchedule[] memory schedules =
            new TharwaDistributorWithVesting.VestingSchedule[](2);
        schedules[0] = TharwaDistributorWithVesting.VestingSchedule(user1, user1Amount);
        schedules[1] = TharwaDistributorWithVesting.VestingSchedule(user2, user2Amount);

        vm.prank(admin);
        distributor.depositVestedAmounts(CAMPAIGN_1, schedules);
        _;
    }

    modifier atVestingStart() {
        vm.warp(startTime);
        _;
    }

    modifier atVestingEnd() {
        vm.warp(endTime);
        _;
    }

    modifier afterVestingEnd() {
        vm.warp(endTime + 1);
        _;
    }

    modifier beforeVestingStart() {
        vm.warp(startTime - 1);
        _;
    }

    modifier atVestingMidpoint() {
        vm.warp(startTime + vestingDuration / 2);
        _;
    }

    modifier atVestingOneThird() {
        vm.warp(startTime + vestingDuration / 3);
        _;
    }

    modifier atVestingTwoThirds() {
        vm.warp(startTime + (vestingDuration * 2) / 3);
        _;
    }
}
