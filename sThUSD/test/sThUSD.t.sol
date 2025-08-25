// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {sThUSD} from "../src/sThUSD.sol";
import {MockERC20} from "./MockERC20.sol";
import {ThUSDSilo} from "../src/ThUSDSilo.sol";

contract sThUSDTest is Test {
    MockERC20 internal thUSD;
    sThUSD internal vault;

    address internal admin;
    address internal user;
    address internal treasury;

    function setUp() public {
        admin = address(this);
        user = makeAddr("user");
        treasury = makeAddr("treasury");

        thUSD = new MockERC20("Tharwa USD", "thUSD", 18);
        vault = new sThUSD(thUSD, admin);

        // Shorten cooldown for tests
        vault.setCooldownPeriod(3 days);

        // Fund user and approve vault
        thUSD.mint(user, 1_000_000e18);
        vm.prank(user);
        thUSD.approve(address(vault), type(uint256).max);
    }

    function test_Unstake_Revert_When_Receiver_Blacklisted() public {
        // Deposit and cooldown thUSD
        vm.prank(user);
        vault.deposit(100e18, user);
        vm.prank(user);
        vault.cooldownAssets(10e18);

        // Wait for cooldown to end
        vm.warp(block.timestamp + vault.cooldownPeriod());

        // Blacklist the receiver and expect revert on unstake
        address recv = makeAddr("recvBL");
        vault.setBlacklisted(recv, true);
        vm.expectRevert(sThUSD.ReceiverBlacklisted.selector);
        vm.prank(user);
        vault.unstake(recv);
    }

    /* ------------------------------- Helpers ------------------------------- */
    function _feeOnRaw(uint256 assets, uint16 feeBps) internal pure returns (uint256) {
        if (feeBps == 0) return 0;
        // ceil(assets * feeBps / 10_000)
        uint256 numer = assets * feeBps;
        uint256 denom = 10_000;
        return numer / denom + (numer % denom == 0 ? 0 : 1);
    }

    function _feeOnTotal(uint256 assets, uint16 feeBps) internal pure returns (uint256) {
        if (feeBps == 0) return 0;
        // ceil(assets * feeBps / (10_000 + feeBps))
        uint256 denom = 10_000 + feeBps;
        uint256 numer = assets * feeBps;
        return numer / denom + (numer % denom == 0 ? 0 : 1);
    }

    /* -------------------------------- Tests -------------------------------- */
    function test_Deposit_NoFee() public {
        uint256 amount = 100e18;
        uint256 userBalBefore = thUSD.balanceOf(user);

        vm.prank(user);
        uint256 sharesMinted = vault.deposit(amount, user);

        assertEq(sharesMinted, amount, "shares 1:1 on empty vault");
        assertEq(vault.balanceOf(user), amount, "user share balance");
        assertEq(vault.totalAssets(), amount, "totalAssets updated");
        assertEq(thUSD.balanceOf(address(vault)), amount, "vault token balance");
        assertEq(thUSD.balanceOf(user), userBalBefore - amount, "user spent assets");

        (uint104 endTs, uint152 amt) = vault.cooldowns(user);
        assertEq(uint256(endTs), 0, "no cooldown after deposit");
        assertEq(uint256(amt), 0, "no amount queued in cooldown");
    }

    function test_MultipleCooldowns_AggregateAndResetTimer() public {
        // Deposit initial thUSD
        vm.prank(user);
        vault.deposit(1_000e18, user);

        // First cooldown 200e18
        vm.prank(user);
        vault.cooldownAssets(200e18);
        (uint104 end1, uint152 amt1) = vault.cooldowns(user);
        assertGt(uint256(end1), block.timestamp, "first cooldown set");
        assertEq(uint256(amt1), 200e18, "amount queued after first cooldown");

        // Warp a bit but not the whole period
        vm.warp(block.timestamp + 1 days);

        // Second cooldown 300e18 -> amount aggregates, timer resets
        vm.prank(user);
        vault.cooldownAssets(300e18);
        (uint104 end2, uint152 amt2) = vault.cooldowns(user);
        assertGt(uint256(end2), block.timestamp, "second cooldown set");
        assertGt(uint256(end2), uint256(end1), "timer reset/extended");
        assertEq(uint256(amt2), 500e18, "amount aggregated");

        // Trying to claim before the latest end should revert
        vm.expectRevert(sThUSD.InvalidCooldown.selector);
        vm.prank(user);
        vault.unstake(user);

        // After the latest cooldown end, claim the full aggregated amount
        vm.warp(uint256(end2));
        uint256 before = thUSD.balanceOf(user);
        vm.prank(user);
        vault.unstake(user);
        assertEq(thUSD.balanceOf(user), before + 500e18, "claimed aggregated amount");

        // Cooldown storage cleared
        (uint104 end3, uint152 amt3) = vault.cooldowns(user);
        assertEq(uint256(end3), 0, "cooldown cleared");
        assertEq(uint256(amt3), 0, "amount cleared");
    }

    function test_Deposit_WithEntryFee() public {
        uint16 entryBps = 100; // 1%
        vault.setFees(entryBps, 0, treasury);

        uint256 amount = 1_000e18;
        uint256 fee = _feeOnTotal(amount, entryBps);

        vm.prank(user);
        uint256 sharesMinted = vault.deposit(amount, user);

        assertEq(sharesMinted, amount - fee, "shares net of entry fee");
        assertEq(vault.balanceOf(user), amount - fee, "user shares");
        assertEq(vault.totalAssets(), amount - fee, "pooled assets net");
        assertEq(thUSD.balanceOf(address(vault)), amount - fee, "vault holds net assets");
        assertEq(thUSD.balanceOf(treasury), fee, "entry fee sent to recipient");
    }

    function test_CooldownAssets_Then_Unstake_NoFee() public {
        uint256 amount = 100e18;
        vm.prank(user);
        vault.deposit(amount, user);

        // withdraw() is disabled when cooldown is ON
        vm.expectRevert(sThUSD.CooldownActive.selector);
        vm.prank(user);
        vault.withdraw(1e18, user, user);

        // Start cooldown for 40e18, receives shares burned according to preview
        uint256 expectedShares = vault.previewWithdraw(40e18);
        vm.prank(user);
        uint256 sharesBurned = vault.cooldownAssets(40e18);
        assertEq(sharesBurned, expectedShares, "shares burned include exit fee (0 here)");

        // Assets moved to silo; pooled assets reduced by 40e18
        assertEq(vault.totalAssets(), 60e18, "pooled assets reduced by cooled amount");
        assertEq(vault.balanceOf(user), amount - expectedShares, "remaining shares after cooldown");

        // Claim after cooldown
        vm.warp(block.timestamp + vault.cooldownPeriod());
        uint256 userBalBefore = thUSD.balanceOf(user);
        vm.prank(user);
        vault.unstake(user);
        assertEq(thUSD.balanceOf(user), userBalBefore + 40e18, "claimed cooled assets");
    }

    function test_CooldownAssets_WithExitFee_Then_Unstake() public {
        // Set exit fee 1%
        uint16 exitBps = 100; // 1%
        vault.setFees(0, exitBps, treasury);

        // Deposit (no entry fee)
        vm.prank(user);
        vault.deposit(1_000e18, user);

        uint256 assetsOut = 500e18;
        uint256 fee = _feeOnRaw(assetsOut, exitBps);
        uint256 expectedShares = assetsOut + fee; // 1:1 share price

        // Preview matches
        uint256 previewShares = vault.previewWithdraw(assetsOut);
        assertEq(previewShares, expectedShares, "previewWithdraw includes fee");

        uint256 feeBalBefore = thUSD.balanceOf(treasury);

        vm.prank(user);
        uint256 returnedShares = vault.cooldownAssets(assetsOut);
        assertEq(returnedShares, expectedShares, "cooldown burns expected shares");

        // Fee paid at cooldown time
        assertEq(thUSD.balanceOf(treasury), feeBalBefore + fee, "exit fee paid on cooldown");

        // Claim after cooldown
        vm.warp(block.timestamp + vault.cooldownPeriod());
        uint256 userBalBefore = thUSD.balanceOf(user);
        vm.prank(user);
        vault.unstake(user);
        assertEq(thUSD.balanceOf(user), userBalBefore + assetsOut, "claimed cooled assets");

        // Pooled assets reduced by assetsOut + fee when cooling down
        assertEq(vault.totalAssets(), 1_000e18 - expectedShares, "pooled assets reduced by net+fee on cooldown");
        assertEq(vault.balanceOf(user), 1_000e18 - expectedShares, "remaining shares after cooldown");
    }

    function test_AddYield_10kVestsOverMonth() public {
        // User provides initial liquidity so totalSupply > 0
        vm.prank(user);
        vault.deposit(100_000e18, user);

        uint256 totalBefore = vault.totalAssets();

        // Admin funds and approves yield
        uint256 yieldAmt = 10_000e18;
        thUSD.mint(admin, yieldAmt);
        thUSD.approve(address(vault), yieldAmt);

        // Add yield and verify immediate accounting
        vault.addYield(yieldAmt);
        assertEq(thUSD.balanceOf(address(vault)), 100_000e18 + yieldAmt, "vault token balance includes yield deposit");
        // All newly added yield is initially unvested -> not in totalAssets
        assertEq(vault.totalAssets(), totalBefore, "no immediate recognition");

        // Halfway through vesting: 50% recognized
        vm.warp(block.timestamp + 15 days);
        assertEq(vault.totalAssets(), totalBefore + yieldAmt / 2, "half of yield recognized after 15 days");

        // Full vesting after 30 days: 100% recognized
        vm.warp(block.timestamp + 15 days);
        assertEq(vault.totalAssets(), totalBefore + yieldAmt, "full yield recognized after 30 days");
    }

    function test_AddYield_RevertWhenActive() public {
        // Ensure there are shares so addYield is allowed
        vm.prank(user);
        vault.deposit(1e18, user);

        // Start vesting
        uint256 yieldAmt = 10_000e18;
        thUSD.mint(admin, yieldAmt);
        thUSD.approve(address(vault), yieldAmt);
        vault.addYield(yieldAmt);

        // Second add while vesting active should revert
        thUSD.mint(admin, 1e18);
        thUSD.approve(address(vault), 1e18);
        vm.expectRevert(sThUSD.VestingActive.selector);
        vault.addYield(1e18);
    }

    function test_UsersEarnYieldProRata() public {
        // Second user setup
        address user2 = makeAddr("user2");
        thUSD.mint(user2, 1_000_000e18);
        vm.prank(user2);
        thUSD.approve(address(vault), type(uint256).max);

        // Both users deposit before yield is added
        vm.startPrank(user);
        thUSD.approve(address(vault), type(uint256).max);
        vault.deposit(100e18, user);
        vm.stopPrank();

        vm.startPrank(user2);
        thUSD.approve(address(vault), type(uint256).max);
        vault.deposit(900e18, user2);
        vm.stopPrank();

        assertEq(vault.totalAssets(), 1_000e18, "initial pooled assets");

        // Admin adds 10,000 thUSD yield
        uint256 y = 10_000e18;
        thUSD.mint(admin, y);
        vm.startPrank(admin);
        thUSD.approve(address(vault), y);
        vault.addYield(y);
        vm.stopPrank();

        // Immediately: unvested, so totalAssets unchanged
        assertEq(vault.totalAssets(), 1_000e18, "no immediate recognition");

        // Enable standard ERC4626 flow: set cooldown OFF
        vault.setCooldownPeriod(0);
        vm.warp(block.timestamp + 30 days);

        // Expected pro-rata amounts
        uint256 expectedA = 100e18 + (y * 100e18) / 1_000e18; // 100 + 1,000 = 1,100e18
        uint256 expectedB = 900e18 + (y * 900e18) / 1_000e18; // 900 + 9,000 = 9,900e18

        // Previews should match expectations without fees
        assertApproxEqAbs(vault.previewRedeem(vault.balanceOf(user)), expectedA, 1, "preview A");
        assertApproxEqAbs(vault.previewRedeem(vault.balanceOf(user2)), expectedB, 10, "preview B");

        // Redeem and verify user balances increase by expected amounts
        uint256 aBefore = thUSD.balanceOf(user);
        uint256 aShares = vault.balanceOf(user);
        vm.prank(user);
        vault.redeem(aShares, user, user);
        uint256 aDelta = thUSD.balanceOf(user) - aBefore;
        assertApproxEqAbs(aDelta, expectedA, 1, "user A earned yield");

        uint256 bBefore = thUSD.balanceOf(user2);
        uint256 bShares = vault.balanceOf(user2);
        vm.prank(user2);
        vault.redeem(bShares, user2, user2);
        uint256 bDelta = thUSD.balanceOf(user2) - bBefore;
        assertApproxEqAbs(bDelta, expectedB, 10, "user B earned yield");

        // Vault drained
        assertEq(vault.totalSupply(), 0, "all shares burned");
        assertLe(vault.totalAssets(), 10, "dust left after rounding");
        assertLe(thUSD.balanceOf(address(vault)), 10, "dust tokens left after rounding");
    }

    function test_FEViewsDuringVesting() public {
        // No vesting yet → all zeros
        assertEq(vault.unvestedAmount(), 0, "no vest: unvested");
        assertEq(vault.vestingStart(), 0, "no vest: start");
        assertEq(vault.vestingEnd(), 0, "no vest: end");
        assertEq(vault.currentYieldRatePerSecond(), 0, "no vest: rate");

        // Ensure supply > 0
        vm.prank(user);
        vault.deposit(1_000e18, user);

        // Add yield now
        uint256 y = 10_000e18;
        thUSD.mint(admin, y);
        thUSD.approve(address(vault), y);
        uint256 t0 = block.timestamp;
        vault.addYield(y);

        uint256 vp = vault.vestingPeriod();
        // At start
        assertEq(vault.unvestedAmount(), y, "start: unvested = full");
        assertEq(vault.vestingStart(), t0, "start: vestingStart");
        assertEq(vault.vestingEnd(), t0 + vp, "start: vestingEnd");
        assertEq(vault.currentYieldRatePerSecond(), y / vp, "start: rate");

        // Halfway
        vm.warp(t0 + vp / 2);
        uint256 expectedUnvestedHalf = (y * (vp - (vp / 2))) / vp; // y/2 (floor)
        assertEq(vault.unvestedAmount(), expectedUnvestedHalf, "mid: unvested");
        assertEq(vault.vestingStart(), t0, "mid: vestingStart persists");
        assertEq(vault.vestingEnd(), t0 + vp, "mid: vestingEnd persists");
        assertEq(vault.currentYieldRatePerSecond(), y / vp, "mid: rate constant");

        // End
        vm.warp(t0 + vp);
        assertEq(vault.unvestedAmount(), 0, "end: unvested = 0");
        assertEq(vault.vestingStart(), 0, "end: start reset");
        assertEq(vault.vestingEnd(), 0, "end: end reset");
        assertEq(vault.currentYieldRatePerSecond(), 0, "end: rate 0");
    }

    function test_CooldownShares_Then_Unstake_NoFee() public {
        vm.prank(user);
        vault.deposit(100e18, user);

        uint256 shares = 40e18;
        uint256 expectedAssets = vault.previewRedeem(shares);

        vm.prank(user);
        uint256 assetsOut = vault.cooldownShares(shares);
        assertEq(assetsOut, expectedAssets, "assets previewed match cooled");

        // pooled assets reduced by assetsOut
        assertEq(vault.totalAssets(), 100e18 - assetsOut, "pooled assets reduced");

        vm.warp(block.timestamp + vault.cooldownPeriod());
        uint256 before = thUSD.balanceOf(user);
        vm.prank(user);
        vault.unstake(user);
        assertEq(thUSD.balanceOf(user), before + assetsOut, "claimed assets from shares cooldown");
    }

    function test_Redeem_Reverts_When_Cooldown_ON() public {
        vm.prank(user);
        vault.deposit(10e18, user);
        vm.expectRevert(sThUSD.CooldownActive.selector);
        vm.prank(user);
        vault.redeem(1e18, user, user);
    }

    function test_SetCooldownPeriod_Allowed_And_Revert() public {
        vault.setCooldownPeriod(0);
        assertEq(vault.cooldownPeriod(), 0, "cooldown off");
        vault.setCooldownPeriod(3 days);
        assertEq(vault.cooldownPeriod(), 3 days, "cooldown 3d");
        vault.setCooldownPeriod(7 days);
        assertEq(vault.cooldownPeriod(), 7 days, "cooldown 7d");
        vm.expectRevert(sThUSD.CooldownNotAllowed.selector);
        vault.setCooldownPeriod(1 days);
    }

    function test_SetFees_Reverts_And_Sets() public {
        // Too high
        vm.expectRevert(sThUSD.FeeTooHigh.selector);
        vault.setFees(1001, 0, treasury);
        vm.expectRevert(sThUSD.FeeTooHigh.selector);
        vault.setFees(0, 1001, treasury);

        // Recipient required when any fee > 0
        vm.expectRevert(sThUSD.RecipientZero.selector);
        vault.setFees(10, 0, address(0));
        vm.expectRevert(sThUSD.RecipientZero.selector);
        vault.setFees(0, 10, address(0));

        // Setting zero fees with zero recipient is ok
        vault.setFees(0, 0, address(0));
        assertEq(vault.entryFeeBps(), 0);
        assertEq(vault.exitFeeBps(), 0);
        assertEq(vault.treasury(), address(0));

        // Setting valid fees and recipient updates state
        vault.setFees(5, 7, treasury);
        assertEq(vault.entryFeeBps(), 5);
        assertEq(vault.exitFeeBps(), 7);
        assertEq(vault.treasury(), treasury);
    }

    function test_Blacklist_Blocks_Transfer_And_Withdraw_Receiver() public {
        // Deposit to get shares
        vm.prank(user);
        vault.deposit(100e18, user);

        // Blacklist user blocks transfers
        vault.setBlacklisted(user, true);
        vm.expectRevert(sThUSD.Blacklisted.selector);
        vm.prank(user);
        vault.transfer(admin, 1e18);

        // Unblacklist user, but blacklist receiver and test withdraw with cooldown OFF
        vault.setBlacklisted(user, false);
        vault.setCooldownPeriod(0); // enable standard ERC4626
        address recv = makeAddr("recv");
        vault.setBlacklisted(recv, true);
        vm.expectRevert(sThUSD.ReceiverBlacklisted.selector);
        vm.prank(user);
        vault.withdraw(1e18, recv, user);
    }

    function test_Pause_Unpause_Guards() public {
        // Pause by PAUSER (admin has role)
        vault.pause();
        vm.expectRevert();
        vm.prank(user);
        vault.deposit(1e18, user);
        vm.expectRevert();
        vm.prank(user);
        vault.cooldownAssets(1e18);
        vm.expectRevert();
        vm.prank(user);
        vault.unstake(user);

        // Unpause restores
        vault.unpause();
        vm.prank(user);
        vault.deposit(1e18, user);
    }

    function test_RescueERC20_NonAsset_And_Asset_Surplus() public {
        // Create another token and send to vault
        MockERC20 other = new MockERC20("Other", "OT", 18);
        other.mint(admin, 1_000e18);
        other.transfer(address(vault), 100e18);

        // Rescue non-asset fully
        vault.rescueERC20(other, admin, 100e18);
        assertEq(other.balanceOf(address(vault)), 0, "rescued other token");

        // Deposit thUSD so pooled assets track correctly
        vm.prank(user);
        vault.deposit(1_000e18, user);

        // Donate extra thUSD directly (surplus)
        thUSD.mint(admin, 50e18);
        thUSD.transfer(address(vault), 50e18);

        // ExceedsSurplus revert
        vm.expectRevert(sThUSD.ExceedsSurplus.selector);
        vault.rescueERC20(thUSD, admin, 51e18);

        // NoSurplus revert when no surplus
        // First rescue surplus
        vault.rescueERC20(thUSD, admin, 50e18);
        // Now try rescuing again (no surplus now)
        vm.expectRevert(sThUSD.NoSurplus.selector);
        vault.rescueERC20(thUSD, admin, 1e18);
    }

    function test_PreviewDeposit_And_PreviewMint_With_EntryFee() public {
        uint16 entry = 100; // 1%
        vault.setFees(entry, 0, treasury);
        // On empty vault: shares minted = assets - fee
        uint256 assets = 1_000e18;
        uint256 fee = _feeOnTotal(assets, entry);
        assertEq(vault.previewDeposit(assets), assets - fee, "previewDeposit accounts entry fee");

        // previewMint: required assets include fee on raw assets
        uint256 shares = 500e18;
        uint256 baseAssets = shares; // 1:1 when empty
        uint256 fee2 = _feeOnRaw(baseAssets, entry);
        assertEq(vault.previewMint(shares), baseAssets + fee2, "previewMint adds fee on raw assets");
    }

    function test_InvalidAmount_Reverts_On_Cooldown() public {
        vm.prank(user);
        vault.deposit(100e18, user);
        vm.expectRevert(sThUSD.InvalidAmount.selector);
        vm.prank(user);
        vault.cooldownAssets(200e18);
        // Precompute shares before expectRevert so the expectation applies to cooldownShares(),
        // not to the intermediate balanceOf() call.
        uint256 tooManyShares = vault.balanceOf(user) + 1;
        vm.expectRevert(sThUSD.InvalidAmount.selector);
        vm.prank(user);
        vault.cooldownShares(tooManyShares);
    }

    function test_Unstake_Allowed_When_Cooldown_Turned_Off() public {
        vm.prank(user);
        vault.deposit(100e18, user);
        vm.prank(user);
        vault.cooldownAssets(10e18);
        // Turn cooldown OFF => should be able to unstake immediately
        vault.setCooldownPeriod(0);
        uint256 before = thUSD.balanceOf(user);
        vm.prank(user);
        vault.unstake(user);
        assertEq(thUSD.balanceOf(user), before + 10e18, "unstake allowed when cooldown off");
    }

    function test_Silo_Views_And_OnlyVault_Guard() public {
        // Check silo points to correct asset and vault
        address silo = address(vault.silo());
        // Call view functions
        assertEq(ThUSDSilo(silo).asset(), address(thUSD), "silo asset");
        assertEq(ThUSDSilo(silo).vault(), address(vault), "silo vault");
        // OnlyVault guard
        vm.expectRevert(ThUSDSilo.OnlyVault.selector);
        ThUSDSilo(silo).withdraw(admin, 1e18);
    }

    function test_decimals_View() public view {
        assertEq(vault.decimals(), 18, "decimals pass-through");
    }

    function test_SetVestingPeriod_RevertOnZero_And_Set() public {
        uint256 prev = vault.vestingPeriod();
        vault.setVestingPeriod(1 days);
        assertEq(vault.vestingPeriod(), 1 days, "set new vesting period");
        vm.expectRevert(sThUSD.PeriodZero.selector);
        vault.setVestingPeriod(0);
        // restore to previous to avoid side effects on other tests
        vault.setVestingPeriod(prev);
    }

    function test_SetVestingPeriod_Revert_When_Vesting_Active() public {
        // Ensure supply > 0
        vm.prank(user);
        vault.deposit(1_000e18, user);

        uint256 prev = vault.vestingPeriod();

        // Start vesting
        uint256 y = 10_000e18;
        thUSD.mint(admin, y);
        thUSD.approve(address(vault), y);
        vault.addYield(y);

        // Changing period mid-vest should revert
        vm.expectRevert(sThUSD.VestingActive.selector);
        vault.setVestingPeriod(1 days);

        // After vesting ends, update should succeed
        vm.warp(block.timestamp + prev);
        vault.setVestingPeriod(1 days);

        // Restore to previous to avoid side effects on other tests
        vault.setVestingPeriod(prev);
    }

    /* -------------------- Additional Branch Coverage -------------------- */
    function test_AddYield_RevertOnZeroAmount() public {
        vm.expectRevert(sThUSD.AmountZero.selector);
        vault.addYield(0);
    }

    function test_AddYield_RevertWhenNoShares() public {
        // totalSupply == 0
        vm.expectRevert(sThUSD.NoShares.selector);
        vault.addYield(1e18);
    }

    function test_CooldownAssets_Revert_When_Off() public {
        vault.setCooldownPeriod(0);
        vm.expectRevert(sThUSD.CooldownIsOff.selector);
        vm.prank(user);
        vault.cooldownAssets(1e18);
    }

    function test_CooldownShares_Revert_When_Off() public {
        vault.setCooldownPeriod(0);
        vm.expectRevert(sThUSD.CooldownIsOff.selector);
        vm.prank(user);
        vault.cooldownShares(1e18);
    }

    function test_CooldownAssets_Revert_On_Zero() public {
        vm.expectRevert(sThUSD.AmountZero.selector);
        vm.prank(user);
        vault.cooldownAssets(0);
    }

    function test_CooldownShares_Revert_On_Zero() public {
        vm.expectRevert(sThUSD.AmountZero.selector);
        vm.prank(user);
        vault.cooldownShares(0);
    }

    function test_Unstake_Revert_When_NoCooledAmount() public {
        vm.expectRevert(sThUSD.AmountZero.selector);
        vm.prank(user);
        vault.unstake(user);
    }

    function test_EntryFee_TreasuryIsVault_SkipsTransfer() public {
        // Set entry fee 1% and treasury to the vault itself
        vault.setFees(100, 0, address(vault));

        uint256 assets = 1_000e18;
        uint256 fee = _feeOnTotal(assets, 100);

        uint256 balBefore = thUSD.balanceOf(address(vault));
        vm.prank(user);
        uint256 sharesMinted = vault.deposit(assets, user);

        // Shares minted net of fee
        assertEq(sharesMinted, assets - fee, "shares net of entry fee");
        // Vault token balance keeps the full assets (no external fee transfer)
        assertEq(thUSD.balanceOf(address(vault)), balBefore + assets, "vault holds full assets; fee retained in-vault");
        // Accounting attributes only net assets
        assertEq(vault.totalAssets(), assets - fee, "pooled assets net of fee");
    }

    function test_ExitFee_TreasuryIsVault_SkipsTransfer_OnCooldown() public {
        // Exit fee 1%, treasury is the vault
        vault.setFees(0, 100, address(vault));

        // Deposit thUSD (no entry fee)
        vm.prank(user);
        vault.deposit(1_000e18, user);

        uint256 assetsOut = 500e18;
        uint256 fee = _feeOnRaw(assetsOut, 100);

        uint256 balBefore = thUSD.balanceOf(address(vault));

        vm.prank(user);
        uint256 burnedShares = vault.cooldownAssets(assetsOut);
        // Required shares include exit fee
        assertEq(burnedShares, assetsOut + fee, "shares include exit fee");

        // Vault transferred only the assets to the silo; fee remained in vault
        assertEq(
            thUSD.balanceOf(address(vault)), balBefore - assetsOut, "only assets moved to silo; fee retained in-vault"
        );
        // Accounting reduced by assets + fee
        assertEq(vault.totalAssets(), 1_000e18 - (assetsOut + fee), "pooled assets reduced by assets+fee");
    }
}
