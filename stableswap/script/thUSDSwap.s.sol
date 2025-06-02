// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {thUSDSwap} from "../src/thUSDSwap.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

contract thUSDSwapScript is Script {
    thUSDSwap public swap;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // uncomment for real network
        // address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        // address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        // address usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        // address thUSD = 0x0000000000000000000000000000000000001337;

        address treasury = 0x0000000000000000000000000000000000001337;

        MockERC20 daiMock = new MockERC20("MockDAI", "DAI", 18);
        MockERC20 usdcMock = new MockERC20("MockUSDC", "USDC", 6);
        MockERC20 usdtMock = new MockERC20("MockUSDT", "USDT", 6);
        MockERC20 thUSDMock = new MockERC20("MockthUSD", "thUSD", 18);

        // swap = new thUSDSwap(dai, usdc, usdt, thUSD);

        swap = new thUSDSwap(
            address(daiMock),
            address(usdcMock),
            address(usdtMock),
            address(thUSDMock),
            treasury
        );

        // transfer thUSD to swap contract
        thUSDMock.mint(address(swap), 100000000 * 10 ** 18);

        console.log("thUSDSwap deployed to:", address(swap));

        vm.stopBroadcast();
    }
}
