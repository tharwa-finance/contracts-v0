// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private mockDecimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) {
        mockDecimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return mockDecimals;
    }

    // everyone can mint only for testing purposes do not use in production
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
