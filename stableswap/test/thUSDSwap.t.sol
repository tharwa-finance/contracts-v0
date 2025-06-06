// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {thUSDSwap} from "../src/thUSDSwap.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract thUSDSwapTest is Test {
    thUSDSwap public swap;
    MockERC20 public dai;
    MockERC20 public usdc;
    MockERC20 public usdt;
    MockERC20 public thUSD;

    address public treasury;

    address public userA;

    function setUp() public {
        userA = makeAddr("userA");

        dai = new MockERC20("DAI", "DAI", 18);
        usdc = new MockERC20("USDC", "USDC", 6);
        usdt = new MockERC20("USDT", "USDT", 6);
        thUSD = new MockERC20("thUSD", "thUSD", 18);

        treasury = makeAddr("treasury");

        swap = new thUSDSwap(
            address(dai),
            address(usdc),
            address(usdt),
            address(thUSD),
            treasury
        );
    }

    function testGetThUSD() public {
        assertEq(swap.getThUSD(), 0);

        thUSD.mint(address(swap), 1000000 * 10 ** 18);

        assertEq(swap.getThUSD(), 1000000 * 10 ** 18);
    }

    function testSwapUSDCForThUSD() public {
        usdc.mint(address(userA), 1000000 * 10 ** 6);

        thUSD.mint(address(swap), 1000000 * 10 ** 18);

        vm.startPrank(userA);
        // current sender balance
        uint256 senderBalance = usdc.balanceOf(address(userA));

        // approve
        usdc.approve(address(swap), senderBalance);

        // swap
        swap.swapUSDC(senderBalance);

        assertEq(thUSD.balanceOf(address(userA)), 1000000 * 10 ** 18);
        assertEq(usdc.balanceOf(address(userA)), 0);

        vm.stopPrank();
    }

    function testSwapDAIForThUSD() public {
        dai.mint(address(userA), 1000000 * 10 ** 18);

        thUSD.mint(address(swap), 1000000 * 10 ** 18);

        vm.startPrank(userA);
        // current sender balance
        uint256 senderBalance = dai.balanceOf(address(userA));

        // approve
        dai.approve(address(swap), senderBalance);

        // swap
        swap.swapDAI(senderBalance);

        assertEq(thUSD.balanceOf(address(userA)), 1000000 * 10 ** 18);
        assertEq(dai.balanceOf(address(userA)), 0);

        vm.stopPrank();
    }

    function testSwapUSDTForThUSD() public {
        usdt.mint(address(userA), 1000000 * 10 ** 6);

        thUSD.mint(address(swap), 1000000 * 10 ** 18);

        vm.startPrank(userA);
        // current sender balance
        uint256 senderBalance = usdt.balanceOf(address(userA));

        // approve
        usdt.approve(address(swap), senderBalance);

        // swap
        swap.swapUSDT(senderBalance);

        assertEq(thUSD.balanceOf(address(userA)), 1000000 * 10 ** 18);
        assertEq(usdt.balanceOf(address(userA)), 0);

        vm.stopPrank();
    }

    function test_WithdrawThUSD() public {
        // mint thUSD to the swap contract
        thUSD.mint(address(swap), 3000000 * 10 ** 18);

        // current balance of treasury
        uint256 treasuryBalance = thUSD.balanceOf(treasury);

        // withdraw thUSD
        vm.prank(address(this));
        swap.MoveThUSDToTreasury(3000000 * 10 ** 18);

        assertEq(
            thUSD.balanceOf(treasury),
            treasuryBalance + 3000000 * 10 ** 18
        );
    }

    function testStablecoinsAreinTreasury() public {
        // mint thUSD to the swap contract
        thUSD.mint(address(swap), 3000000 * 10 ** 18);

        // mint all stablecoins to the userA
        dai.mint(address(userA), 1000000 * 10 ** 18);
        usdc.mint(address(userA), 1000000 * 10 ** 6);
        usdt.mint(address(userA), 1000000 * 10 ** 6);

        // swap
        vm.startPrank(userA);

        // approve
        dai.approve(address(swap), 1000000 * 10 ** 18);
        usdc.approve(address(swap), 1000000 * 10 ** 6);
        usdt.approve(address(swap), 1000000 * 10 ** 6);

        swap.swapDAI(1000000 * 10 ** 18);
        swap.swapUSDC(1000000 * 10 ** 6);
        swap.swapUSDT(1000000 * 10 ** 6);
        vm.stopPrank();

        assertEq(dai.balanceOf(treasury), 1000000 * 10 ** 18);
        assertEq(usdt.balanceOf(treasury), 1000000 * 10 ** 6);
        assertEq(usdc.balanceOf(treasury), 1000000 * 10 ** 6);
    }

    function testRescueERC20() public {
        MockERC20 aToken = new MockERC20("aToken", "aToken", 18);

        aToken.mint(address(swap), 1000000 * 10 ** 18);

        vm.prank(address(this));
        swap.rescueERC20(address(aToken), 1000000 * 10 ** 18);

        assertEq(aToken.balanceOf(address(this)), 1000000 * 10 ** 18);
    }
}
