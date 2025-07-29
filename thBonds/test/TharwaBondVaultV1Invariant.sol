// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console, StdInvariant} from "forge-std/Test.sol";
import {TharwaBondVaultV1} from "../src/TharwaBondVaultV1.sol";
import {MockERC20} from "./MockERC20.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

contract TharwaBondVaultV1Invariant is StdInvariant, Test {
    TharwaBondVaultV1 public vault;
    MockERC20 public thUSD;
    TharwaBondVaultHandler public handler;
    int256 public profit;

    function setUp() public {
        thUSD = new MockERC20(1e27); //  supply
        uint256 initialCap = 1_000_000e18;
        vault = new TharwaBondVaultV1(address(thUSD), initialCap);
        handler = new TharwaBondVaultHandler(this);

        // Tell the fuzzer to call handler functions
        targetContract(address(handler));
    }

    function recordProfit(uint256 p) external {
        profit += int256(p);
    }

    function recordPenalty(uint256 p) external {
        profit -= int256(p);
    }

    // Solvency Invariant: vault balance >= total outstanding liabilities
    function invariant_vaultSolvent() public view {
        uint256 totalLiability = vault.totalOutstanding();
        uint256 vaultBalance = thUSD.balanceOf(address(vault));

        // The vault is solvent if its balance plus the profit it needs to make
        // (the total discount given) equals its total liabilities.
        assertEq(int256(vaultBalance) + profit, int256(totalLiability));
    }
}

contract TharwaBondVaultHandler is Test, IERC1155Receiver {
    TharwaBondVaultV1Invariant public invariantTest;
    TharwaBondVaultV1 public vault;
    MockERC20 public token;

    constructor(TharwaBondVaultV1Invariant _invariantTest) {
        invariantTest = _invariantTest;
        vault = invariantTest.vault();
        token = invariantTest.thUSD();
        token.approve(address(vault), type(uint256).max);
    }

    // Try to subscribe arbitrary amount and tenor
    function purchase(uint256 amount, uint8 tenor) public {
        amount = bound(amount, 1e16, 1e21); // 0.01 – 1,000 tokens
        TharwaBondVaultV1.BondDuration dur = TharwaBondVaultV1.BondDuration(
            tenor % 3
        );
        (uint256 price, , , ) = vault.bondSeries(dur);
        uint256 cost = (amount * price) / 1e18;
        invariantTest.recordProfit(amount - cost);

        deal(address(token), address(this), cost);
        token.approve(address(vault), cost);
        vault.purchaseBond(dur, amount);
    }

    // Attempt early exit of any tokenId we own
    function exit(uint256 tokenId) public {
        uint256 bal = vault.balanceOf(address(this), tokenId);
        if (bal == 0 || block.timestamp >= tokenId) return;

        uint256 payout = vault.earlyExit(tokenId, bal);
        uint256 penalty = bal - payout;
        invariantTest.recordPenalty(penalty);
    }

    // Try redeem matured positions
    function redeem(uint256 tokenId) public {
        if (block.timestamp < tokenId) return;
        uint256 bal = vault.balanceOf(address(this), tokenId);
        if (bal == 0) return;

        // no profit change on redemption
        vault.redeemBond(tokenId);
    }

    // IERC1155Receiver implementation
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) external pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}
