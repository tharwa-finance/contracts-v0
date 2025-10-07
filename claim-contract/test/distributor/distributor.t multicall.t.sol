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

    // Test multicall claiming from multiple tokens for an account using claim()
    function test_multicall_claiming_multiple_tokens_simpleclaim() public {
        uint256 claimAmount1 = 100 ether;
        uint256 claimAmount2 = 200 ether;
        Leaf memory leaf1 = Leaf(user1, address(token1), claimAmount1);
        Leaf memory leaf2 = Leaf(user1, address(token2), claimAmount2);
        Leaf memory leaf3 = Leaf(receiver, address(token2), 200 ether);
        (, bytes32[] memory proof1_, bytes32[] memory proof2_,) = _fillMerkleTree(CAMPAIGN_1, leaf1, leaf2, leaf3);

        // Prepare multicall data
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(
            TharwaDistributor.claim.selector, CAMPAIGN_1, address(token1), claimAmount1, receiver, proof1_
        );
        calls[1] = abi.encodeWithSelector(
            TharwaDistributor.claim.selector, CAMPAIGN_1, address(token2), claimAmount2, receiver, proof2_
        );

        uint256 token1BalanceBefore = token1.balanceOf(receiver);
        uint256 token2BalanceBefore = token2.balanceOf(receiver);

        vm.prank(user1);
        distributor.multicall(calls);

        assertEq(token1.balanceOf(receiver), token1BalanceBefore + claimAmount1);
        assertEq(token2.balanceOf(receiver), token2BalanceBefore + claimAmount2);
        assertEq(distributor.getTotalClaimed(CAMPAIGN_1, user1, address(token1)), claimAmount1);
        assertEq(distributor.getTotalClaimed(CAMPAIGN_1, user1, address(token2)), claimAmount2);
    }

    // Test multicall claiming from multiple tokens for an account using claimOnBehalf()
    function test_multicall_claiming_multiple_tokens_claimOnBehalf() public {
        uint256 claimAmount1 = 100 ether;
        uint256 claimAmount2 = 200 ether;
        Leaf memory leaf1 = Leaf(user1, address(token1), claimAmount1);
        Leaf memory leaf2 = Leaf(user1, address(token2), claimAmount2);
        Leaf memory leaf3 = Leaf(user2, address(token2), 200 ether);
        (, bytes32[] memory proof1_, bytes32[] memory proof2_,) = _fillMerkleTree(CAMPAIGN_1, leaf1, leaf2, leaf3);

        // Prepare multicall data
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(
            TharwaDistributor.claimOnBehalf.selector, CAMPAIGN_1, user1, address(token1), claimAmount1, proof1_
        );
        calls[1] = abi.encodeWithSelector(
            TharwaDistributor.claimOnBehalf.selector, CAMPAIGN_1, user1, address(token2), claimAmount2, proof2_
        );

        uint256 token1BalanceBefore = token1.balanceOf(user1);
        uint256 token2BalanceBefore = token2.balanceOf(user1);

        vm.prank(user2);
        distributor.multicall(calls);

        assertEq(token1.balanceOf(user1), token1BalanceBefore + claimAmount1);
        assertEq(token2.balanceOf(user1), token2BalanceBefore + claimAmount2);
        assertEq(distributor.getTotalClaimed(CAMPAIGN_1, user1, address(token1)), claimAmount1);
        assertEq(distributor.getTotalClaimed(CAMPAIGN_1, user1, address(token2)), claimAmount2);
    }

    // Test multicall claiming from multiple campaigns a single token and an account using claim()
    function test_multicall_claiming_multiple_campaigns_claim() public {
        uint256 claimAmount1 = 100 ether;
        uint256 claimAmount2 = 200 ether;

        Leaf memory leaf1 = Leaf(user1, address(token1), claimAmount1);
        Leaf memory leaf2 = Leaf(user1, address(token2), 70 ether);
        Leaf memory leaf3 = Leaf(user2, address(token2), 200 ether);
        (, bytes32[] memory proof1_,,) = _fillMerkleTree(CAMPAIGN_1, leaf1, leaf2, leaf3);

        Leaf memory leaf4 = Leaf(user1, address(token1), claimAmount2);
        Leaf memory leaf5 = Leaf(user1, address(token2), 90 ether);
        Leaf memory leaf6 = Leaf(user2, address(token2), 300 ether);
        (, bytes32[] memory proof4_,,) = _fillMerkleTree(CAMPAIGN_2, leaf4, leaf5, leaf6);

        // Prepare multicall data
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(
            TharwaDistributor.claim.selector, CAMPAIGN_1, address(token1), claimAmount1, receiver, proof1_
        );
        calls[1] = abi.encodeWithSelector(
            TharwaDistributor.claim.selector, CAMPAIGN_2, address(token1), claimAmount2, receiver, proof4_
        );

        uint256 tokenBalanceBefore = token1.balanceOf(receiver);

        vm.prank(user1);
        distributor.multicall(calls);

        assertEq(token1.balanceOf(receiver), tokenBalanceBefore + claimAmount1 + claimAmount2);
        assertEq(distributor.getTotalClaimed(CAMPAIGN_1, user1, address(token1)), claimAmount1);
        assertEq(distributor.getTotalClaimed(CAMPAIGN_2, user1, address(token1)), claimAmount2);
    }

    // Test multicall claiming from multiple campaigns a single token and an account using claimOnBehalf()
    function test_multicall_claiming_multiple_campaigns_claimOnBehalf() public {
        uint256 claimAmount1 = 100 ether;
        uint256 claimAmount2 = 200 ether;

        Leaf memory leaf1 = Leaf(user1, address(token1), claimAmount1);
        Leaf memory leaf2 = Leaf(user1, address(token2), 70 ether);
        Leaf memory leaf3 = Leaf(user2, address(token2), 200 ether);
        (, bytes32[] memory proof1_,,) = _fillMerkleTree(CAMPAIGN_1, leaf1, leaf2, leaf3);

        Leaf memory leaf4 = Leaf(user1, address(token1), claimAmount2);
        Leaf memory leaf5 = Leaf(user1, address(token2), 90 ether);
        Leaf memory leaf6 = Leaf(user2, address(token2), 300 ether);
        (, bytes32[] memory proof4_,,) = _fillMerkleTree(CAMPAIGN_2, leaf4, leaf5, leaf6);

        // Prepare multicall data
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(
            TharwaDistributor.claimOnBehalf.selector, CAMPAIGN_1, user1, address(token1), claimAmount1, proof1_
        );
        calls[1] = abi.encodeWithSelector(
            TharwaDistributor.claimOnBehalf.selector, CAMPAIGN_2, user1, address(token1), claimAmount2, proof4_
        );

        uint256 tokenBalanceBefore = token1.balanceOf(user1);

        vm.prank(user2);
        distributor.multicall(calls);

        assertEq(token1.balanceOf(user1), tokenBalanceBefore + claimAmount1 + claimAmount2);
        assertEq(distributor.getTotalClaimed(CAMPAIGN_1, user1, address(token1)), claimAmount1);
        assertEq(distributor.getTotalClaimed(CAMPAIGN_2, user1, address(token1)), claimAmount2);
    }
}
