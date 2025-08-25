// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
▗▄▄▄▖▗▖ ▗▖ ▗▄▖ ▗▄▄▖ ▗▖ ▗▖ ▗▄▖ 
  █  ▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌
  █  ▐▛▀▜▌▐▛▀▜▌▐▛▀▚▖▐▌ ▐▌▐▛▀▜▌
  █  ▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▙█▟▌▐▌ ▐▌

visit : https://tharwa.finance
*/

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ThUSDSilo
/// @notice Minimal silo to hold thUSD during cooldown for sThUSD vault.
contract ThUSDSilo {
    address private immutable _VAULT;
    IERC20 private immutable _ASSET;

    error OnlyVault();

    constructor(address vault_, address asset_) {
        _VAULT = vault_;
        _ASSET = IERC20(asset_);
    }

    function withdraw(address to, uint256 amount) external {
        if (msg.sender != _VAULT) revert OnlyVault();
        _ASSET.transfer(to, amount);
    }

    function asset() external view returns (address) {
        return address(_ASSET);
    }

    function vault() external view returns (address) {
        return _VAULT;
    }
}
