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
        // address frxUSD = 0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29;
        // address thUSD = 0x76972F054aB43829064d31fF5f3AcC5Fabe57FE8;

        address treasury = 0xe58DB0F0D38D952B40E4f583c32dE9a9CD0160C3;
        // swap = new thUSDSwap(dai, usdc, usdt, frxUSD, thUSD, treasury);

        // sepolia testnet addresses
        address daiMock = 0x5574a42Bed488430Fe9F2B901dfB2B98AC2Cf939;
        address usdcMock = 0xf558D32cd178d99D59097093DebB65b9ADf2180e;
        address usdtMock = 0x24a9c379D5852fF66C2D09d4290429fafcAf9e26;
        address frxUSDMock = 0x5E41316B0E2Adfc53a017c9a19C308C6d2FaA1F3;
        address thUSDMock = 0xBDa089250C2bd31db65C99a99D4862d6BAC4446A;

        swap = new thUSDSwap(
            address(daiMock),
            address(usdcMock),
            address(usdtMock),
            address(frxUSDMock),
            address(thUSDMock),
            treasury
        );

        // transfer thUSD to swap contract
        // thUSDMock.mint(address(swap), 1000000 * 10 ** 18);

        console.log("thUSDSwap deployed to:", address(swap));

        vm.stopBroadcast();
    }
}
