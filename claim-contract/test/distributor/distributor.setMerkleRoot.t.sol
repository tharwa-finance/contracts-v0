// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TharwaDistributor} from "src/TharwaDistributor.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {MerkleProof} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import {TestDistributorBase, Leaf} from "test/distributor/distributor.base.t.sol";

contract UpdateRootTests is TestDistributorBase {
    function setUp() public override {
        super.setUp();
    }

    function test_set_merkle_root_successfully_by_admin() public {
        bytes32 newRoot = bytes32(uint256(123));

        vm.expectEmit(true, false, false, true);
        emit TharwaDistributor.MerkleRootUpdated(CAMPAIGN_1, newRoot);

        vm.prank(admin);
        distributor.updateMerkleRoot(CAMPAIGN_1, newRoot);

        assertEq(distributor.merkleRoots(CAMPAIGN_1), newRoot);
    }

    // Test set merkle root reverts when not admin
    function test_set_merkle_root_reverts_when_not_admin() public {
        bytes32 newRoot = bytes32(uint256(123));

        vm.prank(user1);
        // todo this revert should be more specific
        vm.expectRevert();
        distributor.updateMerkleRoot(CAMPAIGN_1, newRoot);
    }

    // test set merkle root reverts when setting to zero
    function test_set_merkle_root_reverts_when_setting_to_zero() public {
        bytes32 newRoot = bytes32(0);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(TharwaDistributor.ExpectedNonZero.selector));
        distributor.updateMerkleRoot(CAMPAIGN_1, newRoot);
    }

    // Test verify the merkle proof increases claimable amount for an account,token,campaign
    function test_verify_merkle_proof_increases_claimable_amount() public {
        uint256 user1Amount = 100 ether;
        uint256 user2Amount = 50 ether;
        Leaf memory leaf1 = Leaf(user1, address(token1), user1Amount);
        Leaf memory leaf2 = Leaf(user2, address(token1), user2Amount);
        Leaf memory leaf3 = Leaf(user2, address(token2), 200 ether);
        (, bytes32[] memory proof1_, bytes32[] memory proof2_,) = _fillMerkleTree(CAMPAIGN_1, leaf1, leaf2, leaf3);

        assertEq(distributor.getClaimableAmount(CAMPAIGN_1, user1, address(token1), user1Amount, proof1_), user1Amount);
        assertEq(distributor.getClaimableAmount(CAMPAIGN_1, user2, address(token1), user2Amount, proof2_), user2Amount);
    }

    // Test verify the merkle proof increases claimable amount for an account,token,campaign for 5 leafs
    function test_verify_merkle_proof_increases_claimable_amount_for_3_leafs() public {
        Leaf memory leaf1 = Leaf(user1, address(token1), 100 ether);
        Leaf memory leaf2 = Leaf(user1, address(token2), 200 ether);
        Leaf memory leaf3 = Leaf(user2, address(token1), 50 ether);

        (bytes32 root, bytes32[] memory proof1, bytes32[] memory proof2, bytes32[] memory proof3) =
            _createThreeLeafTree(leaf1, leaf2, leaf3);

        vm.prank(admin);
        distributor.updateMerkleRoot(CAMPAIGN_1, root);

        assertEq(distributor.getClaimableAmount(CAMPAIGN_1, user1, address(token1), 100 ether, proof1), 100 ether);
        assertEq(distributor.getClaimableAmount(CAMPAIGN_1, user1, address(token2), 200 ether, proof2), 200 ether);
        assertEq(distributor.getClaimableAmount(CAMPAIGN_1, user2, address(token1), 50 ether, proof3), 50 ether);
    }
}
