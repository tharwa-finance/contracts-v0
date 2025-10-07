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
import {MerkleProof} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import {Multicall} from "lib/openzeppelin-contracts/contracts/utils/Multicall.sol";

/* ─── Tharwa Staked Version ──────────────────────────────────────────────── */
/// @title Tharwa Distributor contract (points claims)
/// @author @jacopod - github.com/JacoboLansac
/// @notice Merkle-root based contract with campaigns for users to claim their rewards
contract TharwaDistributor is Ownable, Multicall {
    /// @notice Root of a Merkle tree per campaign.
    /// @dev The leaves should be `(address account, address token, uint amount)`
    /// @dev The `amount` is a cumulative only-increasing value for each (account, token) pair.
    mapping(uint256 campaign => bytes32 root) public merkleRoots;

    /// @notice Total amounts historically claimed per campaign per account per token
    mapping(uint256 campaign => mapping(address account => mapping(address token => uint256 totalClaimed))) private
        _totalClaimed;

    ////////////////// Events ////////////////
    event MerkleRootUpdated(uint256 indexed campaign, bytes32 newRoot);
    event Claimed(
        uint256 indexed campaign, address indexed account, address indexed token, uint256 amount, address receiver
    );

    ////////////////// Errors ////////////////
    error ExpectedNonZero();
    error InvalidProof();
    error InsufficientClaimableAmount();
    error TokenTransferFailed();

    constructor() Ownable(msg.sender) {}

    ///////////////////// Admin functions //////////////////////
    function updateMerkleRoot(uint256 campaign, bytes32 newRoot) public onlyOwner {
        // once a campaign is set, it cannot be unset by passing a zero root
        require(newRoot != bytes32(0), ExpectedNonZero());

        emit MerkleRootUpdated(campaign, newRoot);
        merkleRoots[campaign] = newRoot;
    }

    ///////////////////// External functions //////////////////////

    /// @notice Claim tokens for `msg.sender` and send them to `receiver`
    /// @dev intended for normal users, allowing to send tokens to a different address
    /// @param campaign The campaign id
    /// @param token The address of the token to claim
    /// @param totalClaimableSinceStart The total claimable amount since the start of the campaign
    /// @param receiver The address that will receive the claimed tokens
    /// @param proof The merkle proof to validate the claim
    function claim(
        uint256 campaign,
        address token,
        uint256 totalClaimableSinceStart,
        address receiver,
        bytes32[] calldata proof
    ) external {
        _claim(campaign, msg.sender, token, totalClaimableSinceStart, proof, receiver);
    }

    /// @notice Claim tokens on behalf of `account`, sending them to `account`
    /// @dev intended for claims on behalf of contracts that don't have the claiming logic implemented
    /// @dev the caller doesn't receive the tokens, they are sent to `account`
    /// @param campaign The campaign id
    /// @param account The address of the account to claim for
    /// @param token The address of the token to claim
    /// @param totalClaimableSinceStart The total claimable amount since the start of the campaign
    /// @param proof The merkle proof to validate the claim
    function claimOnBehalf(
        uint256 campaign,
        address account,
        address token,
        uint256 totalClaimableSinceStart,
        bytes32[] calldata proof
    ) external {
        _claim(campaign, account, token, totalClaimableSinceStart, proof, account);
    }

    ///////////////////// View functions //////////////////////

    /// @notice Get the total amount already claimed by `account` for `token` in `campaign`
    /// @param campaign The campaign id
    /// @param account The address of the account
    /// @param token The address of the token
    /// @return The total amount already claimed
    function getTotalClaimed(uint256 campaign, address account, address token) public view returns (uint256) {
        return _totalClaimed[campaign][account][token];
    }

    /// @notice Get the claimable amount by `account` for `token` in `campaign`
    /// @dev If the totalClaimableAmout is same as already claimed, it returns 0
    /// @dev If the merkle proof is invalid or totalClaimable is less than already claimed, it returns 0
    /// @param campaign The campaign id
    /// @param account The address of the account
    /// @param token The address of the token
    /// @param totalClaimableAmount The total claimable amount since the start of the campaign
    /// @param proof The merkle proof to validate the claimable amount
    /// @return The claimable amount (totalClaimableAmount - alreadyClaimed)
    function getClaimableAmount(
        uint256 campaign,
        address account,
        address token,
        uint256 totalClaimableAmount,
        bytes32[] calldata proof
    ) public view returns (uint256) {
        if (!_verifyProof(campaign, account, token, totalClaimableAmount, proof)) {
            return 0;
        }

        uint256 alreadyClaimed = _totalClaimed[campaign][account][token];
        if (totalClaimableAmount <= alreadyClaimed) {
            return 0;
        }

        return totalClaimableAmount - alreadyClaimed;
    }

    ///////////////////// Internal functions //////////////////////

    function _claim(
        uint256 campaign,
        address account,
        address token,
        uint256 totalClaimableSinceStart,
        bytes32[] calldata proof,
        address receiver
    ) internal {
        require(totalClaimableSinceStart > 0, ExpectedNonZero());
        require(_verifyProof(campaign, account, token, totalClaimableSinceStart, proof), InvalidProof());

        // If this requirement is not met, it is a mistake in the off-chain calculations
        uint256 alreadyClaimed = _totalClaimed[campaign][account][token];
        require(totalClaimableSinceStart >= alreadyClaimed, InsufficientClaimableAmount());

        uint256 claimAmount = totalClaimableSinceStart - alreadyClaimed;
        if (claimAmount == 0) return;

        _totalClaimed[campaign][account][token] = totalClaimableSinceStart;

        emit Claimed(campaign, account, token, claimAmount, receiver);

        SafeERC20.safeTransfer(IERC20(token), receiver, claimAmount);
    }

    function _verifyProof(uint256 campaign, address account, address token, uint256 amount, bytes32[] calldata proof)
        internal
        view
        returns (bool)
    {
        bytes32 leaf = keccak256(abi.encodePacked(account, token, amount));
        return MerkleProof.verify(proof, merkleRoots[campaign], leaf);
    }
}
