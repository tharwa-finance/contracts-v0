// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract TharwaMock is ERC20 {
    constructor() ERC20("Tharwa", "THR") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
