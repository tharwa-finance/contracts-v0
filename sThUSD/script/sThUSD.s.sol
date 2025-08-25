// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {sThUSD} from "../src/sThUSD.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract sThUSDScript is Script {
    function run() public {
        vm.startBroadcast();

        //testnet mock token public mint
        //IERC20 thUSD = IERC20(0xBDa089250C2bd31db65C99a99D4862d6BAC4446A);

        //mainnet thUSD
        IERC20 thUSD = IERC20(0x76972F054aB43829064d31fF5f3AcC5Fabe57FE8);
        new sThUSD(thUSD, msg.sender);

        vm.stopBroadcast();
    }

    // Coverage workaround: Foundry currently includes .s.sol in coverage.
    // Defining a `test`-prefixed function makes the file ignored by coverage.
    function test() public {}
}
