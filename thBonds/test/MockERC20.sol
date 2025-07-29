// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(uint256 initialSupply) ERC20("MockTHUSD", "mTHUSD") {
        _mint(msg.sender, initialSupply);
    }
}
