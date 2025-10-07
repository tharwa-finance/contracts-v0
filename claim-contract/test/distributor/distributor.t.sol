// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TharwaDistributor} from "src/TharwaDistributor.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {MerkleProof} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import {TestDistributorBase, Leaf} from "test/distributor/distributor.base.t.sol";

contract DistributorClaimTests is TestDistributorBase {
    function setUp() public override {
        super.setUp();
    }

    function _withBasicMerkleTree(Leaf memory leaf1) internal returns (bytes32 root_, bytes32[] memory proof_) {
        // input leaf1 and create the other two with other inputs
        Leaf memory leaf2 = Leaf(user2, address(token1), 50 ether);
        Leaf memory leaf3 = Leaf(user1, address(token2), 200 ether);
        bytes32[] memory proof2_;
        bytes32[] memory proof3_;

        (root_, proof_, proof2_, proof3_) = _createThreeLeafTree(leaf1, leaf2, leaf3);

        vm.prank(admin);
        distributor.updateMerkleRoot(CAMPAIGN_1, root_);
    }

    // Test claim successfully by msg.sender to msg.sender. Check Correct balances
    function test_claim_successfully_by_sender_to_sender_balances() public {
        uint256 claimAmount = 100 ether;
        (, bytes32[] memory proof) = _withBasicMerkleTree(Leaf(user1, address(token1), claimAmount));

        uint256 userBalanceBefore = token1.balanceOf(user1);
        uint256 distributorBalanceBefore = token1.balanceOf(address(distributor));

        vm.prank(user1);
        distributor.claim(CAMPAIGN_1, address(token1), claimAmount, user1, proof);

        assertEq(token1.balanceOf(user1), userBalanceBefore + claimAmount);
        assertEq(token1.balanceOf(address(distributor)), distributorBalanceBefore - claimAmount);
        assertEq(distributor.getTotalClaimed(CAMPAIGN_1, user1, address(token1)), claimAmount);
    }

    // Test claim successfully by msg.sender to msg.sender. Check Correct event
    function test_claim_successfully_by_sender_to_sender_event() public {
        uint256 claimAmount = 100 ether;
        (, bytes32[] memory proof) = _withBasicMerkleTree(Leaf(user1, address(token1), claimAmount));

        vm.expectEmit(true, true, true, true);
        emit TharwaDistributor.Claimed(CAMPAIGN_1, user1, address(token1), claimAmount, user1);

        vm.prank(user1);
        distributor.claim(CAMPAIGN_1, address(token1), claimAmount, user1, proof);
    }

    // Test claim successfully by msg.sender to receiver. Check Correct balances
    function test_claim_successfully_by_sender_to_receiver_balances() public {
        uint256 claimAmount = 100 ether;
        (, bytes32[] memory proof) = _withBasicMerkleTree(Leaf(user1, address(token1), claimAmount));

        uint256 receiverBalanceBefore = token1.balanceOf(receiver);
        uint256 distributorBalanceBefore = token1.balanceOf(address(distributor));

        vm.prank(user1);
        distributor.claim(CAMPAIGN_1, address(token1), claimAmount, receiver, proof);

        assertEq(token1.balanceOf(receiver), receiverBalanceBefore + claimAmount);
        assertEq(token1.balanceOf(address(distributor)), distributorBalanceBefore - claimAmount);
        assertEq(distributor.getTotalClaimed(CAMPAIGN_1, user1, address(token1)), claimAmount);
    }

    // Test claim successfully by msg.sender to receiver. Check Correct event
    function test_claim_successfully_by_sender_to_receiver_event() public {
        uint256 claimAmount = 100 ether;
        (, bytes32[] memory proof) = _withBasicMerkleTree(Leaf(user1, address(token1), claimAmount));

        vm.expectEmit(true, true, true, true);
        emit TharwaDistributor.Claimed(CAMPAIGN_1, user1, address(token1), claimAmount, receiver);

        vm.prank(user1);
        distributor.claim(CAMPAIGN_1, address(token1), claimAmount, receiver, proof);
    }

    // Test claim successfully on behalf of an account. Check Correct balances
    function test_claim_successfully_on_behalf_balances() public {
        uint256 claimAmount = 100 ether;
        (, bytes32[] memory proof) = _withBasicMerkleTree(Leaf(user1, address(token1), claimAmount));

        uint256 user1BalanceBefore = token1.balanceOf(user1);
        uint256 user2BalanceBefore = token1.balanceOf(user2);
        uint256 distributorBalanceBefore = token1.balanceOf(address(distributor));

        vm.prank(user2);
        distributor.claimOnBehalf(CAMPAIGN_1, user1, address(token1), claimAmount, proof);

        assertEq(token1.balanceOf(user2), user2BalanceBefore);
        assertEq(token1.balanceOf(user1), user1BalanceBefore + claimAmount);
        assertEq(token1.balanceOf(address(distributor)), distributorBalanceBefore - claimAmount);
        assertEq(distributor.getTotalClaimed(CAMPAIGN_1, user1, address(token1)), claimAmount);
    }

    // Test claim successfully on behalf of an account. Check Correct event
    function test_claim_successfully_on_behalf_event() public {
        uint256 claimAmount = 100 ether;
        (, bytes32[] memory proof) = _withBasicMerkleTree(Leaf(user1, address(token1), claimAmount));

        vm.expectEmit(true, true, true, true);
        emit TharwaDistributor.Claimed(CAMPAIGN_1, user1, address(token1), claimAmount, user1);

        vm.prank(user2);
        distributor.claimOnBehalf(CAMPAIGN_1, user1, address(token1), claimAmount, proof);
    }

    // Test claim twice with same root and proof silently returns, and no balance changes take place
    function test_claim_twice_silently_returns() public {
        uint256 claimAmount = 123 ether;
        (, bytes32[] memory proof) = _withBasicMerkleTree(Leaf(user1, address(token1), claimAmount));

        // First claim
        vm.prank(user1);
        distributor.claim(CAMPAIGN_1, address(token1), claimAmount, receiver, proof);

        uint256 receiverBalanceAfterFirst = token1.balanceOf(receiver);
        uint256 distributorBalanceAfterFirst = token1.balanceOf(address(distributor));

        // Second claim should not emit event and should not change balances
        vm.prank(user1);
        distributor.claim(CAMPAIGN_1, address(token1), claimAmount, receiver, proof);

        assertEq(token1.balanceOf(receiver), receiverBalanceAfterFirst);
        assertEq(token1.balanceOf(address(distributor)), distributorBalanceAfterFirst);
        assertEq(distributor.getTotalClaimed(CAMPAIGN_1, user1, address(token1)), claimAmount);
    }

    // Test claim reverts if claimableAmount is zero
    function test_claim_reverts_if_claimable_amount_zero() public {
        uint256 claimAmount = 123 ether;
        (, bytes32[] memory proof) = _withBasicMerkleTree(Leaf(user1, address(token1), claimAmount));

        vm.prank(user1);
        vm.expectRevert(TharwaDistributor.ExpectedNonZero.selector);
        distributor.claim(CAMPAIGN_1, address(token1), 0, receiver, proof);
    }

    // Test claim reverts if claimableAmount is less than already claimed
    function test_claim_reverts_if_amount_less_than_claimed() public {
        uint256 claimAmount = 123 ether;
        (, bytes32[] memory proof1) = _withBasicMerkleTree(Leaf(user1, address(token1), claimAmount));

        // First claim
        vm.prank(user1);
        distributor.claim(CAMPAIGN_1, address(token1), claimAmount, receiver, proof1);

        // new root is set, with a smaller amount
        uint256 newTotalClaimableAmount = claimAmount - 50 ether;
        (, bytes32[] memory proof2) = _withBasicMerkleTree(Leaf(user1, address(token1), newTotalClaimableAmount));

        // Second claim should revert because newTotalClaimableAmount is less of what already was claimed
        vm.prank(user1);
        vm.expectRevert(TharwaDistributor.InsufficientClaimableAmount.selector);
        distributor.claim(CAMPAIGN_1, address(token1), newTotalClaimableAmount, user1, proof2);
    }

    // Test silently returns if new merkle has the same amount associated to an account,token,campaign
    function test_claim_silently_returns_same_amount() public {
        uint256 claimAmount = 125 ether;
        (, bytes32[] memory proof1) = _withBasicMerkleTree(Leaf(user1, address(token1), claimAmount));

        // First claim
        vm.prank(user1);
        distributor.claim(CAMPAIGN_1, address(token1), claimAmount, receiver, proof1);

        uint256 receiverBalanceAfterFirst = token1.balanceOf(receiver);
        uint256 distributorBalanceAfterFirst = token1.balanceOf(address(distributor));

        // Create a new root with same first leaf, changing others
        Leaf memory leaf1 = Leaf(user1, address(token1), claimAmount);
        Leaf memory leaf2 = Leaf(user2, address(token1), 100 ether);
        Leaf memory leaf3 = Leaf(user1, address(token2), 200 ether);
        // overwrite proof1_ with the new leaf
        (, proof1,,) = _fillMerkleTree(CAMPAIGN_1, leaf1, leaf2, leaf3);

        // Second claim should not change balances for user 1 with leaf1
        vm.prank(user1);
        distributor.claim(CAMPAIGN_1, address(token1), claimAmount, receiver, proof1);

        assertEq(token1.balanceOf(receiver), receiverBalanceAfterFirst);
        assertEq(token1.balanceOf(address(distributor)), distributorBalanceAfterFirst);
    }

    // Test claiming one token does not affect totalClaimed or claimable amounts of other tokens
    function test_claiming_one_token_does_not_affect_other_tokens() public {
        uint256 claimAmount = 50 ether;
        Leaf memory leaf1 = Leaf(user1, address(token1), claimAmount);
        Leaf memory leaf2 = Leaf(user1, address(token2), 70 ether);
        Leaf memory leaf3 = Leaf(user2, address(token2), 200 ether);
        (, bytes32[] memory proof1_, bytes32[] memory proof2_,) = _fillMerkleTree(CAMPAIGN_1, leaf1, leaf2, leaf3);

        assertEq(distributor.getClaimableAmount(CAMPAIGN_1, user1, address(token1), claimAmount, proof1_), claimAmount);
        assertEq(distributor.getClaimableAmount(CAMPAIGN_1, user1, address(token2), 70 ether, proof2_), 70 ether);

        // Claim token1
        vm.prank(user1);
        distributor.claim(CAMPAIGN_1, address(token1), claimAmount, receiver, proof1_);

        // the claimable amount for token2 should be intact
        assertEq(distributor.getClaimableAmount(CAMPAIGN_1, user1, address(token1), claimAmount, proof1_), 0);
        assertEq(distributor.getClaimableAmount(CAMPAIGN_1, user1, address(token2), 70 ether, proof2_), 70 ether);
        assertEq(distributor.getTotalClaimed(CAMPAIGN_1, user1, address(token1)), 50 ether);
        assertEq(distributor.getTotalClaimed(CAMPAIGN_1, user1, address(token2)), 0);
    }

    // Test claiming one token does not affect totalClaimed or claimable amounts of other accounts
    function test_claiming_one_token_does_not_affect_other_accounts() public {
        uint256 claimAmount1 = 50 ether;
        uint256 claimAmount2 = 70 ether;
        Leaf memory leaf1 = Leaf(user1, address(token1), claimAmount1);
        Leaf memory leaf2 = Leaf(user2, address(token1), claimAmount2);
        Leaf memory leaf3 = Leaf(user2, address(token2), 200 ether);
        (, bytes32[] memory proof1_, bytes32[] memory proof2_,) = _fillMerkleTree(CAMPAIGN_1, leaf1, leaf2, leaf3);

        assertEq(
            distributor.getClaimableAmount(CAMPAIGN_1, user1, address(token1), claimAmount1, proof1_), claimAmount1
        );
        assertEq(
            distributor.getClaimableAmount(CAMPAIGN_1, user2, address(token1), claimAmount2, proof2_), claimAmount2
        );

        // Claim token1 for user1
        vm.prank(user1);
        distributor.claim(CAMPAIGN_1, address(token1), claimAmount1, receiver, proof1_);

        // the claimable amount for user2 should be intact
        assertEq(distributor.getClaimableAmount(CAMPAIGN_1, user1, address(token1), claimAmount1, proof1_), 0);
        assertEq(
            distributor.getClaimableAmount(CAMPAIGN_1, user2, address(token1), claimAmount2, proof2_), claimAmount2
        );
        assertEq(distributor.getTotalClaimed(CAMPAIGN_1, user2, address(token1)), 0);
        assertEq(distributor.getTotalClaimed(CAMPAIGN_1, user1, address(token1)), claimAmount1);
    }

    // Test claiming one token does not affect totalClaimed or claimable amounts of other campaigns
    function test_claiming_one_token_does_not_affect_other_campaigns() public {
        Leaf memory leaf1 = Leaf(user1, address(token1), 50 ether);
        Leaf memory leaf2 = Leaf(user1, address(token2), 70 ether);
        Leaf memory leaf3 = Leaf(user2, address(token2), 200 ether);
        (, bytes32[] memory proof1_, ,) = _fillMerkleTree(CAMPAIGN_1, leaf1, leaf2, leaf3);

        Leaf memory leaf4 = Leaf(user1, address(token1), 80 ether);
        Leaf memory leaf5 = Leaf(user1, address(token2), 90 ether);
        Leaf memory leaf6 = Leaf(user2, address(token2), 300 ether);
        (, bytes32[] memory proof4_, ,) = _fillMerkleTree(CAMPAIGN_2, leaf4, leaf5, leaf6);

        assertEq(distributor.getClaimableAmount(CAMPAIGN_1, user1, address(token1), 50 ether, proof1_), 50 ether);
        assertEq(distributor.getClaimableAmount(CAMPAIGN_2, user1, address(token1), 80 ether, proof4_), 80 ether);

        // Claim token1 for user1 in campaign 1
        vm.prank(user1);
        distributor.claim(CAMPAIGN_1, address(token1), 50 ether, receiver, proof1_);

        // the claimable amount for campaign 2 should be intact
        assertEq(distributor.getClaimableAmount(CAMPAIGN_1, user1, address(token1), 50 ether, proof1_), 0);
        assertEq(distributor.getClaimableAmount(CAMPAIGN_2, user1, address(token1), 80 ether, proof4_), 80 ether);
        assertEq(distributor.getTotalClaimed(CAMPAIGN_1, user1, address(token1)), 50 ether);
        assertEq(distributor.getTotalClaimed(CAMPAIGN_2, user1, address(token1)), 0);
    }

    // Test claim reverts if merkle proof is invalid
    function test_claim_reverts_if_merkle_proof_invalid() public {
        uint256 claimAmount = 100 ether;

        // Create invalid proof
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = bytes32(uint256(999));

        vm.prank(user1);
        vm.expectRevert(TharwaDistributor.InvalidProof.selector);
        distributor.claim(CAMPAIGN_1, address(token1), claimAmount, receiver, invalidProof);
    }

    // Test claim reverts if merkle root is not set for a campaign
    function test_claim_reverts_if_merkle_root_not_set() public {
        uint256 claimAmount = 100 ether;
        bytes32[] memory proof_ = new bytes32[](0);

        vm.prank(user1);
        vm.expectRevert(TharwaDistributor.InvalidProof.selector);
        distributor.claim(CAMPAIGN_1, address(token1), claimAmount, receiver, proof_);
    }

    // test that getClaimableAmount is updated correctly after a merkleroot set, then claim, then new merkleroot set
    function test_getClaimableAmount_updated_correctly_after_claim_and_new_root() public {
        uint256 initialClaimAmount = 100 ether;
        (, bytes32[] memory proof1) = _withBasicMerkleTree(Leaf(user1, address(token1), initialClaimAmount));

        assertEq(
            distributor.getClaimableAmount(CAMPAIGN_1, user1, address(token1), initialClaimAmount, proof1),
            initialClaimAmount
        );

        vm.prank(user1);
        distributor.claim(CAMPAIGN_1, address(token1), initialClaimAmount, receiver, proof1);

        assertEq(distributor.getTotalClaimed(CAMPAIGN_1, user1, address(token1)), initialClaimAmount);

        // Set a new root with a higher total claimable amount
        uint256 newTotalClaimableAmount = 150 ether;
        (, bytes32[] memory proof2) = _withBasicMerkleTree(Leaf(user1, address(token1), newTotalClaimableAmount));

        // The new claimable amount should be the difference between new total and already claimed
        assertEq(
            distributor.getClaimableAmount(CAMPAIGN_1, user1, address(token1), newTotalClaimableAmount, proof2),
            newTotalClaimableAmount - initialClaimAmount
        );
    }

    // test get claimable amount with invalid proof returns 0
    function test_getClaimableAmount_with_invalid_proof_returns_0() public view {
        uint256 claimAmount = 100 ether;

        // Create invalid proof
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = bytes32(uint256(999));

        assertEq(distributor.getClaimableAmount(CAMPAIGN_1, user1, address(token1), claimAmount, invalidProof), 0);
    }
}
