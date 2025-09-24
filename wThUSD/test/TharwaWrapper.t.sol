// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {wThUSD} from "src/wThUSD.sol";
import {TharwaWrapper} from "src/TharwaWrapper.sol";

contract BaseTests is Test {
    wThUSD public wthusd;
    IERC20 public thUsd;
    address public constant THUSD_ADDRESS = 0x76972F054aB43829064d31fF5f3AcC5Fabe57FE8;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public owner = makeAddr("owner");

    uint256 public constant INITIAL_BALANCE = 10000e18;

    modifier withDeposit(address user, uint256 amount) {
        vm.prank(user);
        wthusd.deposit(amount, user);
        _;
    }

    function setUp() public virtual {
        uint256 block_number = 23349642;
        string memory rpcUrl = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(rpcUrl, block_number);

        thUsd = IERC20(THUSD_ADDRESS);

        vm.prank(owner);
        wthusd = new wThUSD(thUsd);

        deal(THUSD_ADDRESS, alice, INITIAL_BALANCE);
        deal(THUSD_ADDRESS, bob, INITIAL_BALANCE);

        vm.prank(alice);
        thUsd.approve(address(wthusd), type(uint256).max);

        vm.prank(bob);
        thUsd.approve(address(wthusd), type(uint256).max);
    }
}

contract DepositTests is BaseTests {
    function test_deposit_success() public {
        uint256 depositAmount = 1000e18;
        uint256 initialBalance = thUsd.balanceOf(alice);

        vm.prank(alice);
        uint256 shares = wthusd.deposit(depositAmount, alice);

        assertEq(shares, depositAmount);
        assertEq(wthusd.balanceOf(alice), depositAmount);
        assertEq(thUsd.balanceOf(alice), initialBalance - depositAmount);
        assertEq(thUsd.balanceOf(address(wthusd)), depositAmount);
    }

    function test_deposit_toReceiver() public {
        uint256 depositAmount = 1000e18;

        vm.prank(alice);
        uint256 shares = wthusd.deposit(depositAmount, bob);

        assertEq(shares, depositAmount);
        assertEq(wthusd.balanceOf(bob), depositAmount);
        assertEq(wthusd.balanceOf(alice), 0);
    }

    function test_deposit_zeroAmount() public {
        vm.prank(alice);
        uint256 shares = wthusd.deposit(0, alice);

        assertEq(shares, 0);
        assertEq(wthusd.balanceOf(alice), 0);
    }

    function test_deposit_insufficientBalance() public {
        uint256 excessiveAmount = INITIAL_BALANCE + 1;

        vm.prank(alice);
        vm.expectRevert();
        wthusd.deposit(excessiveAmount, alice);
    }

    function test_deposit_insufficientAllowance() public {
        uint256 depositAmount = 1000e18;

        vm.prank(alice);
        thUsd.approve(address(wthusd), depositAmount - 1);

        vm.prank(alice);
        vm.expectRevert();
        wthusd.deposit(depositAmount, alice);
    }

    function test_deposit_emitsEvent() public {
        uint256 depositAmount = 1000e18;

        vm.expectEmit(true, true, true, true);
        emit IERC4626.Deposit(alice, alice, depositAmount, depositAmount);

        vm.prank(alice);
        wthusd.deposit(depositAmount, alice);
    }
}

contract MintTests is BaseTests {
    function test_mint_success() public {
        uint256 sharesToMint = 1000e18;
        uint256 initialBalance = thUsd.balanceOf(alice);

        vm.prank(alice);
        uint256 assets = wthusd.mint(sharesToMint, alice);

        assertEq(assets, sharesToMint);
        assertEq(wthusd.balanceOf(alice), sharesToMint);
        assertEq(thUsd.balanceOf(alice), initialBalance - sharesToMint);
        assertEq(thUsd.balanceOf(address(wthusd)), sharesToMint);
    }

    function test_mint_toReceiver() public {
        uint256 sharesToMint = 1000e18;

        vm.prank(alice);
        uint256 assets = wthusd.mint(sharesToMint, bob);

        assertEq(assets, sharesToMint);
        assertEq(wthusd.balanceOf(bob), sharesToMint);
        assertEq(wthusd.balanceOf(alice), 0);
    }

    function test_mint_zeroShares() public {
        vm.prank(alice);
        uint256 assets = wthusd.mint(0, alice);

        assertEq(assets, 0);
        assertEq(wthusd.balanceOf(alice), 0);
    }
}

contract WithdrawTests is BaseTests {
    function test_withdraw_success() public withDeposit(alice, 2000e18) {
        uint256 withdrawAmount = 1000e18;
        uint256 initialBalance = thUsd.balanceOf(alice);

        vm.prank(alice);
        uint256 shares = wthusd.withdraw(withdrawAmount, alice, alice);

        assertEq(shares, withdrawAmount);
        assertEq(wthusd.balanceOf(alice), 1000e18);
        assertEq(thUsd.balanceOf(alice), initialBalance + withdrawAmount);
    }

    function test_withdraw_toReceiver() public withDeposit(alice, 2000e18) {
        uint256 withdrawAmount = 1000e18;
        uint256 initialBobBalance = thUsd.balanceOf(bob);

        vm.prank(alice);
        uint256 shares = wthusd.withdraw(withdrawAmount, bob, alice);

        assertEq(shares, withdrawAmount);
        assertEq(wthusd.balanceOf(alice), 1000e18);
        assertEq(thUsd.balanceOf(bob), initialBobBalance + withdrawAmount);
    }

    function test_withdraw_withAllowance() public withDeposit(alice, 2000e18) {
        uint256 withdrawAmount = 1000e18;

        vm.prank(alice);
        wthusd.approve(bob, withdrawAmount);

        vm.prank(bob);
        uint256 shares = wthusd.withdraw(withdrawAmount, bob, alice);

        assertEq(shares, withdrawAmount);
        assertEq(wthusd.balanceOf(alice), 1000e18);
        assertEq(wthusd.allowance(alice, bob), 0);
    }

    function test_withdraw_insufficientShares() public withDeposit(alice, 1000e18) {
        uint256 excessiveAmount = 1500e18;

        vm.prank(alice);
        vm.expectRevert();
        wthusd.withdraw(excessiveAmount, alice, alice);
    }

    function test_withdraw_insufficientAllowance() public withDeposit(alice, 2000e18) {
        uint256 withdrawAmount = 1000e18;

        vm.prank(alice);
        wthusd.approve(bob, withdrawAmount - 1);

        vm.prank(bob);
        vm.expectRevert();
        wthusd.withdraw(withdrawAmount, bob, alice);
    }

    function test_withdraw_emitsEvent() public withDeposit(alice, 2000e18) {
        uint256 withdrawAmount = 1000e18;

        vm.expectEmit(true, true, true, true);
        emit IERC4626.Withdraw(alice, alice, alice, withdrawAmount, withdrawAmount);

        vm.prank(alice);
        wthusd.withdraw(withdrawAmount, alice, alice);
    }
}

contract RedeemTests is BaseTests {
    function test_redeem_success() public withDeposit(alice, 2000e18) {
        uint256 sharesToRedeem = 1000e18;
        uint256 initialBalance = thUsd.balanceOf(alice);

        vm.prank(alice);
        uint256 assets = wthusd.redeem(sharesToRedeem, alice, alice);

        assertEq(assets, sharesToRedeem);
        assertEq(wthusd.balanceOf(alice), 1000e18);
        assertEq(thUsd.balanceOf(alice), initialBalance + sharesToRedeem);
    }

    function test_redeem_toReceiver() public withDeposit(alice, 2000e18) {
        uint256 sharesToRedeem = 1000e18;
        uint256 initialBobBalance = thUsd.balanceOf(bob);

        vm.prank(alice);
        uint256 assets = wthusd.redeem(sharesToRedeem, bob, alice);

        assertEq(assets, sharesToRedeem);
        assertEq(wthusd.balanceOf(alice), 1000e18);
        assertEq(thUsd.balanceOf(bob), initialBobBalance + sharesToRedeem);
    }

    function test_redeem_withAllowance() public withDeposit(alice, 2000e18) {
        uint256 sharesToRedeem = 1000e18;

        vm.prank(alice);
        wthusd.approve(bob, sharesToRedeem);

        vm.prank(bob);
        uint256 assets = wthusd.redeem(sharesToRedeem, bob, alice);

        assertEq(assets, sharesToRedeem);
        assertEq(wthusd.balanceOf(alice), 1000e18);
        assertEq(wthusd.allowance(alice, bob), 0);
    }

    function test_redeem_zeroShares() public {
        vm.prank(alice);
        uint256 assets = wthusd.redeem(0, alice, alice);

        assertEq(assets, 0);
    }
}

contract ViewFunctionTests is BaseTests {
    function test_convertToShares() public {
        uint256 assets = 1000e18;
        uint256 shares = wthusd.convertToShares(assets);
        assertEq(shares, assets);
    }

    function test_convertToAssets() public {
        uint256 shares = 1000e18;
        uint256 assets = wthusd.convertToAssets(shares);
        assertEq(assets, shares);
    }

    function test_previewDeposit() public {
        uint256 assets = 1000e18;
        uint256 expectedShares = wthusd.previewDeposit(assets);
        assertEq(expectedShares, assets);
    }

    function test_previewMint() public {
        uint256 shares = 1000e18;
        uint256 expectedAssets = wthusd.previewMint(shares);
        assertEq(expectedAssets, shares);
    }

    function test_previewWithdraw() public {
        uint256 assets = 1000e18;
        uint256 expectedShares = wthusd.previewWithdraw(assets);
        assertEq(expectedShares, assets);
    }

    function test_previewRedeem() public {
        uint256 shares = 1000e18;
        uint256 expectedAssets = wthusd.previewRedeem(shares);
        assertEq(expectedAssets, shares);
    }

    function test_maxDeposit() public {
        uint256 maxDeposit = wthusd.maxDeposit(alice);
        assertEq(maxDeposit, type(uint256).max);
    }

    function test_maxMint() public {
        uint256 maxMint = wthusd.maxMint(alice);
        assertEq(maxMint, type(uint256).max);
    }

    function test_maxWithdraw() public withDeposit(alice, 1000e18) {
        uint256 maxWithdraw = wthusd.maxWithdraw(alice);
        assertEq(maxWithdraw, 1000e18);
    }

    function test_maxRedeem() public withDeposit(alice, 1000e18) {
        uint256 maxRedeem = wthusd.maxRedeem(alice);
        assertEq(maxRedeem, 1000e18);
    }

    function test_asset() public {
        address asset = wthusd.asset();
        assertEq(asset, THUSD_ADDRESS);
    }

    function test_totalAssets() public withDeposit(alice, 1000e18) {
        uint256 totalAssets = wthusd.totalAssets();
        assertEq(totalAssets, 1000e18);
    }
}

contract OwnerTests is BaseTests {
    function test_rescueErc20Token_nonAsset() public {
        ERC20Mock otherToken = new ERC20Mock();
        uint256 amount = 1000e18;

        otherToken.mint(address(wthusd), amount);

        vm.prank(owner);
        wthusd.rescueErc20Token(IERC20(otherToken), amount, owner);

        assertEq(otherToken.balanceOf(owner), amount);
    }

    function test_rescueErc20Token_asset_excess() public withDeposit(alice, 1000e18) {
        uint256 excess = 500e18;
        deal(THUSD_ADDRESS, address(wthusd), 1500e18);

        vm.prank(owner);
        wthusd.rescueErc20Token(thUsd, excess, owner);

        assertEq(thUsd.balanceOf(owner), excess);
        assertEq(thUsd.balanceOf(address(wthusd)), 1000e18);
    }

    function test_rescueErc20Token_asset_tooMuch() public withDeposit(alice, 1000e18) {
        uint256 excessiveAmount = 1500e18;
        deal(THUSD_ADDRESS, address(wthusd), 1000e18);

        vm.prank(owner);
        vm.expectRevert("Rescue amount to high");
        wthusd.rescueErc20Token(thUsd, excessiveAmount, owner);
    }

    function test_rescueErc20Token_onlyOwner() public {
        ERC20Mock otherToken = new ERC20Mock();
        uint256 amount = 1000e18;

        vm.prank(alice);
        vm.expectRevert();
        wthusd.rescueErc20Token(IERC20(otherToken), amount, alice);
    }

    function test_ownershipTransfer() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        wthusd.transferOwnership(newOwner);

        assertEq(wthusd.owner(), newOwner);
    }
}

contract EdgeCaseTests is BaseTests {
    function test_depositWithdrawFullBalance() public {
        uint256 fullBalance = INITIAL_BALANCE;

        vm.prank(alice);
        wthusd.deposit(fullBalance, alice);

        assertEq(wthusd.balanceOf(alice), fullBalance);
        assertEq(thUsd.balanceOf(alice), 0);

        vm.prank(alice);
        wthusd.withdraw(fullBalance, alice, alice);

        assertEq(wthusd.balanceOf(alice), 0);
        assertEq(thUsd.balanceOf(alice), fullBalance);
    }

    function test_multipleUsersDepositsAndWithdrawals() public {
        uint256 aliceDeposit = 1000e18;
        uint256 bobDeposit = 2000e18;

        vm.prank(alice);
        wthusd.deposit(aliceDeposit, alice);

        vm.prank(bob);
        wthusd.deposit(bobDeposit, bob);

        assertEq(wthusd.totalSupply(), aliceDeposit + bobDeposit);
        assertEq(wthusd.totalAssets(), aliceDeposit + bobDeposit);

        vm.prank(alice);
        wthusd.withdraw(aliceDeposit, alice, alice);

        assertEq(wthusd.balanceOf(alice), 0);
        assertEq(wthusd.balanceOf(bob), bobDeposit);
        assertEq(wthusd.totalSupply(), bobDeposit);
    }

    function test_depositZeroToZeroAddress() public {
        vm.prank(alice);
        vm.expectRevert();
        wthusd.deposit(1000e18, address(0));
    }

    function test_withdrawToZeroAddress() public withDeposit(alice, 1000e18) {
        vm.prank(alice);
        vm.expectRevert();
        wthusd.withdraw(500e18, address(0), alice);
    }

    function test_allowanceEdgeCases() public withDeposit(alice, 2000e18) {
        vm.prank(alice);
        wthusd.approve(bob, 1000e18);

        vm.prank(bob);
        wthusd.withdraw(500e18, bob, alice);

        assertEq(wthusd.allowance(alice, bob), 500e18);

        vm.prank(alice);
        wthusd.approve(bob, type(uint256).max);

        vm.prank(bob);
        wthusd.withdraw(500e18, bob, alice);

        assertEq(wthusd.allowance(alice, bob), type(uint256).max);
    }

    function test_fuzzDeposit(uint256 amount) public {
        amount = bound(amount, 0, INITIAL_BALANCE);

        vm.prank(alice);
        uint256 shares = wthusd.deposit(amount, alice);

        assertEq(shares, amount);
        assertEq(wthusd.balanceOf(alice), amount);
    }

    function test_fuzzWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 1, INITIAL_BALANCE);
        withdrawAmount = bound(withdrawAmount, 0, depositAmount);

        vm.prank(alice);
        wthusd.deposit(depositAmount, alice);

        vm.prank(alice);
        uint256 shares = wthusd.withdraw(withdrawAmount, alice, alice);

        assertEq(shares, withdrawAmount);
        assertEq(wthusd.balanceOf(alice), depositAmount - withdrawAmount);
    }
}

interface IERC4626 {
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
}
