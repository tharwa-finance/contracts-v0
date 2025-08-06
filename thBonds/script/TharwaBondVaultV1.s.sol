// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TharwaBondVaultV1} from "../src/TharwaBondVaultV1.sol";

contract TharwaBondVaultV1Script is Script {
    TharwaBondVaultV1 public vault;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        // thUSD - sepolia address thUSD = 0xBDa089250C2bd31db65C99a99D4862d6BAC4446A;
        address thUSD = 0x76972F054aB43829064d31fF5f3AcC5Fabe57FE8;
        uint256 initialCap = 1 * 100_000 * 1e18;
        vault = new TharwaBondVaultV1(thUSD, initialCap);

        vm.stopBroadcast();
    }
}
