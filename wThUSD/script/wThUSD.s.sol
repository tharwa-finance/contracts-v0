// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {wThUSD} from "src/wThUSD.sol";
import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract DeployWThUSD is Script {
    function run() public {
        vm.startBroadcast();

        address thUsd = vm.envAddress("THUSD_ADDRESS");
        wThUSD wthusd = new wThUSD(IERC20(thUsd));
        console.log("wThUSD deployed to: ", address(wthusd));

        vm.stopBroadcast();
    }
}
