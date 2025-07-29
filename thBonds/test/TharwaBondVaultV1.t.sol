// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {TharwaBondVaultV1} from "../src/TharwaBondVaultV1.sol";
import {MockERC20} from "./MockERC20.sol";
import {IERC1155Receiver, IERC165} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

contract TharwaBondVaultV1Test is Test, IERC1155Receiver {
    TharwaBondVaultV1 public vault;
    MockERC20 public thUSD;

    function setUp() public {
        thUSD = new MockERC20(100 * 1_000_000 * 1e18);
        uint256 initialCap = 1 * 1_000_000 * 1e18;

        vault = new TharwaBondVaultV1(address(thUSD), initialCap);
    }

    function testPurchaseBond() public {
        // Approve vault to spend THUSD
        thUSD.approve(address(vault), 1000e18);

        // Execute purchase
        vault.purchaseBond(TharwaBondVaultV1.BondDuration.NinetyDays, 1000e18);

        // Compute expected tokenId (maturity timestamp rounded to midnight UTC)
        uint256 maturity = ((block.timestamp + 90 days) / 1 days) * 1 days;
        assertEq(vault.balanceOf(address(this), maturity), 1000e18);
    }

    function testEarlyExit() public {
        thUSD.approve(address(vault), 1000e18);
        vault.purchaseBond(TharwaBondVaultV1.BondDuration.NinetyDays, 1000e18);
        uint256 maturity = ((block.timestamp + 90 days) / 1 days) * 1 days;

        // Calculate expected payout according to contract formula
        uint256 daysLeft = (maturity - block.timestamp) / 1 days + 1;
        uint256 pen = daysLeft * 0.002e18;
        if (pen > 0.20e18) pen = 0.20e18;
        uint256 expectedPayout = (1000e18 * (1e18 - pen)) / 1e18;

        uint256 balBefore = thUSD.balanceOf(address(this));
        vault.earlyExit(maturity, 1000e18);
        assertEq(thUSD.balanceOf(address(this)), balBefore + expectedPayout);
        assertEq(vault.balanceOf(address(this), maturity), 0);
    }

    function testRedeemBond() public {
        thUSD.approve(address(vault), 1000e18);
        vault.purchaseBond(TharwaBondVaultV1.BondDuration.NinetyDays, 1000e18);
        uint256 maturity = ((block.timestamp + 90 days) / 1 days) * 1 days;

        // Ensure vault has enough THUSD to cover full face value
        thUSD.transfer(address(vault), 1000e18);

        vm.warp(maturity + 1);
        uint256 balBefore = thUSD.balanceOf(address(this));
        vault.redeemBond(maturity);
        assertEq(thUSD.balanceOf(address(this)), balBefore + 1000e18);
        assertEq(vault.balanceOf(address(this), maturity), 0);
    }

    function testSetBondPriceAndCap() public {
        vault.setBondPrice(TharwaBondVaultV1.BondDuration.NinetyDays, 0.90e18);
        vault.setBondCap(TharwaBondVaultV1.BondDuration.NinetyDays, 2e18);
        (uint256 price, , uint256 cap, ) = vault.bondSeries(
            TharwaBondVaultV1.BondDuration.NinetyDays
        );
        assertEq(price, 0.90e18);
        assertEq(cap, 2e18);
    }

    function testSetURI() public {
        string memory newURI = "https://example.com/{id}.json";
        vault.setURI(newURI);
        assertEq(vault.uri(0), newURI);
    }

    function testPurchaseBondZeroAmountRevert() public {
        vm.expectRevert(TharwaBondVaultV1.ZeroAmount.selector);
        vault.purchaseBond(TharwaBondVaultV1.BondDuration.NinetyDays, 0);
    }

    function testPurchaseBondCapExceededRevert() public {
        // Reduce cap to 1e18 face value and attempt to purchase 2e18
        vault.setBondCap(TharwaBondVaultV1.BondDuration.NinetyDays, 1e18);
        thUSD.approve(address(vault), 2e18);
        vm.expectRevert(TharwaBondVaultV1.CapExceeded.selector);
        vault.purchaseBond(TharwaBondVaultV1.BondDuration.NinetyDays, 2e18);
    }

    function testEarlyExitBondMaturedRevert() public {
        thUSD.approve(address(vault), 1e18);
        vault.purchaseBond(TharwaBondVaultV1.BondDuration.NinetyDays, 1e18);
        uint256 maturity = ((block.timestamp + 90 days) / 1 days) * 1 days;
        // Warp past maturity so the bond is matured
        vm.warp(maturity + 1);
        vm.expectRevert(TharwaBondVaultV1.BondMatured.selector);
        vault.earlyExit(maturity, 1e18);
    }

    function testRedeemBondNotMaturedRevert() public {
        thUSD.approve(address(vault), 1e18);
        vault.purchaseBond(TharwaBondVaultV1.BondDuration.NinetyDays, 1e18);
        uint256 maturity = ((block.timestamp + 90 days) / 1 days) * 1 days;
        vm.expectRevert(TharwaBondVaultV1.BondNotMatured.selector);
        vault.redeemBond(maturity);
    }

    function testSetBondPriceInvalidRevert() public {
        vm.expectRevert(TharwaBondVaultV1.InvalidPrice.selector);
        vault.setBondPrice(TharwaBondVaultV1.BondDuration.NinetyDays, 1e18);
    }

    function testEarlyExitMaxPenaltyCapped() public {
        // 180-day bond should trigger max penalty cap when exiting immediately
        thUSD.approve(address(vault), 1e18);
        vault.purchaseBond(TharwaBondVaultV1.BondDuration.OneEightyDays, 1e18);
        uint256 maturity = ((block.timestamp + 180 days) / 1 days) * 1 days;

        uint256 expectedPayout = (1e18 * (1e18 - 0.20e18)) / 1e18; // 20% max penalty
        uint256 balBefore = thUSD.balanceOf(address(this));
        vault.earlyExit(maturity, 1e18);
        assertEq(thUSD.balanceOf(address(this)), balBefore + expectedPayout);
    }

    function test_RevertOnMaturityCollision() public {
        // Setup users Alice and Bob
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        deal(address(thUSD), alice, 1000e18);
        deal(address(thUSD), bob, 500e18);
        vm.prank(alice);
        thUSD.approve(address(vault), 1000e18);
        vm.prank(bob);
        thUSD.approve(address(vault), 500e18);

        // Alice purchases a 360-day bond.
        vm.prank(alice);
        vault.purchaseBond(
            TharwaBondVaultV1.BondDuration.ThreeSixtyDays,
            1000e18
        );

        // Fast-forward time so that a 90-day bond purchased now
        // will mature on the exact same day as Alice's bond.
        vm.warp(block.timestamp + 270 days);

        // Bob attempts to purchase a 90-day bond that collides with Alice's.
        // The contract must revert.
        vm.prank(bob);
        vm.expectRevert(TharwaBondVaultV1.MaturityCollision.selector);
        vault.purchaseBond(TharwaBondVaultV1.BondDuration.NinetyDays, 500e18);

        // wait a a day try again
        vm.warp(block.timestamp + 1 days);
        vm.prank(bob);
        vault.purchaseBond(TharwaBondVaultV1.BondDuration.NinetyDays, 500e18);
    }

    function testTotalOutstanding() public {
        thUSD.approve(address(vault), 3e18);

        vault.purchaseBond(TharwaBondVaultV1.BondDuration.NinetyDays, 1e18);
        vault.purchaseBond(TharwaBondVaultV1.BondDuration.OneEightyDays, 1e18);
        vault.purchaseBond(TharwaBondVaultV1.BondDuration.ThreeSixtyDays, 1e18);
        assertEq(vault.totalOutstanding(), 3e18);
    }

    function testRescueTokens() public {
        thUSD.approve(address(vault), 1e18);
        vault.purchaseBond(TharwaBondVaultV1.BondDuration.NinetyDays, 1e18);

        (uint256 price, , , ) = vault.bondSeries(
            TharwaBondVaultV1.BondDuration.NinetyDays
        );
        uint256 cost = (1e18 * price) / 1e18;

        assertEq(thUSD.balanceOf(address(vault)), cost);

        uint256 balBefore = thUSD.balanceOf(address(this));
        vault.rescueTokens(address(thUSD), address(this), cost);
        assertEq(thUSD.balanceOf(address(this)), balBefore + cost);
    }

    function testGetBondsForUser() public {
        thUSD.approve(address(vault), 2e18);
        vault.purchaseBond(TharwaBondVaultV1.BondDuration.NinetyDays, 1e18);
        vault.purchaseBond(TharwaBondVaultV1.BondDuration.OneEightyDays, 1e18);

        uint256 maturity90 = ((block.timestamp + 90 days) / 1 days) * 1 days;
        uint256 maturity180 = ((block.timestamp + 180 days) / 1 days) * 1 days;

        uint256[] memory bonds = vault.getBondsForUser(address(this));
        assertEq(bonds.length, 2);

        bool has90;
        bool has180;
        for (uint256 i = 0; i < bonds.length; i++) {
            if (bonds[i] == maturity90) has90 = true;
            if (bonds[i] == maturity180) has180 = true;
        }
        assertTrue(has90 && has180);
    }

    /* support IERC1155Receiver */
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
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
    ) public pure override returns (bool) {
        return
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }
}
