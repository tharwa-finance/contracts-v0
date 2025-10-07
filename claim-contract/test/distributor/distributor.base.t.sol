// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TharwaDistributor} from "src/TharwaDistributor.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {MerkleProof} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

struct Leaf {
    address account;
    address token;
    uint256 amount;
}

contract TestDistributorBase is Test {
    TharwaDistributor public distributor;
    ERC20Mock public token1;
    ERC20Mock public token2;

    address admin = makeAddr("admin");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address receiver = makeAddr("receiver");

    uint256 constant CAMPAIGN_1 = 1;
    uint256 constant CAMPAIGN_2 = 2;

    function setUp() public virtual {
        vm.prank(admin);
        distributor = new TharwaDistributor();

        token1 = new ERC20Mock();
        token2 = new ERC20Mock();

        // Mint tokens to distributor for distribution
        token1.mint(address(distributor), 1000000 ether);
        token2.mint(address(distributor), 1000000 ether);
    }

    function test_deployment() public view {
        assertEq(distributor.owner(), admin);
    }

    function _fillMerkleTree(uint256 campaign, Leaf memory leaf1, Leaf memory leaf2, Leaf memory leaf3)
        internal
        returns (bytes32 root_, bytes32[] memory proof_, bytes32[] memory proof2_, bytes32[] memory proof3_)
    {
        (root_, proof_, proof2_, proof3_) = _createThreeLeafTree(leaf1, leaf2, leaf3);

        vm.prank(admin);
        distributor.updateMerkleRoot(campaign, root_);
    }

    // Utility functions for creating merkle trees and proofs
    function _hashLeaf(address account, address token, uint256 amount) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(account, token, amount));
    }

    function _createThreeLeafTree(Leaf memory leaf1, Leaf memory leaf2, Leaf memory leaf3)
        internal
        pure
        returns (bytes32 root, bytes32[] memory proof1, bytes32[] memory proof2, bytes32[] memory proof3)
    {
        bytes32 hashLeaf1 = _hashLeaf(leaf1.account, leaf1.token, leaf1.amount);
        bytes32 hashLeaf2 = _hashLeaf(leaf2.account, leaf2.token, leaf2.amount);
        bytes32 hashLeaf3 = _hashLeaf(leaf3.account, leaf3.token, leaf3.amount);

        // Sort hashes for consistent tree structure
        bytes32[] memory hashes = new bytes32[](3);
        hashes[0] = hashLeaf1;
        hashes[1] = hashLeaf2;
        hashes[2] = hashLeaf3;

        // Simple bubble sort for 3 elements
        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = 0; j < 2 - i; j++) {
                if (hashes[j] > hashes[j + 1]) {
                    bytes32 temp = hashes[j];
                    hashes[j] = hashes[j + 1];
                    hashes[j + 1] = temp;
                }
            }
        }

        // Build tree: pair first two leaves, then combine with third
        bytes32 node1 = keccak256(abi.encodePacked(hashes[0], hashes[1]));
        root = keccak256(abi.encodePacked(node1, hashes[2]));

        // Generate proofs for each original leaf
        proof1 = _generateThreeLeafProof(hashLeaf1, hashes);
        proof2 = _generateThreeLeafProof(hashLeaf2, hashes);
        proof3 = _generateThreeLeafProof(hashLeaf3, hashes);
    }

    function _generateThreeLeafProof(bytes32 targetHash, bytes32[] memory sortedHashes)
        internal
        pure
        returns (bytes32[] memory proof)
    {
        uint256 targetIndex;

        // Find target hash position in sorted array
        for (uint256 i = 0; i < 3; i++) {
            if (sortedHashes[i] == targetHash) {
                targetIndex = i;
                break;
            }
        }

        proof = new bytes32[](2);

        if (targetIndex < 2) {
            // First two leaves (indices 0,1)
            proof[0] = targetIndex == 0 ? sortedHashes[1] : sortedHashes[0]; // sibling
            proof[1] = sortedHashes[2]; // third leaf
        } else {
            // Third leaf (index 2)
            proof[0] = keccak256(abi.encodePacked(sortedHashes[0], sortedHashes[1])); // node1
            // Only 1 element needed for proof of the third leaf
            bytes32[] memory shortProof = new bytes32[](1);
            shortProof[0] = proof[0];
            return shortProof;
        }
    }
}
