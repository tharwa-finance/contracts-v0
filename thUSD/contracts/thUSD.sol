// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
▗▄▄▄▖▗▖ ▗▖ ▗▄▖ ▗▄▄▖ ▗▖ ▗▖ ▗▄▖ 
  █  ▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌
  █  ▐▛▀▜▌▐▛▀▜▌▐▛▀▚▖▐▌ ▐▌▐▛▀▜▌
  █  ▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▙█▟▌▐▌ ▐▌


visit : https://tharwa.finance                         
*/

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title thUSD - Tharwa USD Stablecoin
/// @notice An ERC20 token with OFT (Omnichain Fungible Token) functionality for cross-chain transfers
/// @dev Inherits from OpenZeppelin's Pausable and LayerZero's OFT contracts
contract thUSD is OFT, Pausable {
    /// @notice Mapping to track blacklisted addresses
    /// @dev Addresses in this mapping are restricted from all token transfers and approvals
    mapping(address => bool) public isBlacklisted;

    /// @notice Emitted when an address is added to the blacklist
    /// @param account The address that was blacklisted
    event Blacklisted(address indexed account);

    /// @notice Emitted when an address is removed from the blacklist
    /// @param account The address that was unblacklisted
    event Unblacklisted(address indexed account);

    /// @notice Error thrown when a blacklisted user attempts a restricted action
    /// @param user The address that is blacklisted
    error UserBlacklisted(address user);

    /// @notice Constructs the thUSD token contract
    /// @param _name The name of the token
    /// @param _symbol The symbol of the token (e.g., thUSD)
    /// @param _lzEndpoint The LayerZero endpoint address for cross-chain functionality
    /// @param _delegate The initial owner/delegate address with admin privileges
    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate
    ) OFT(_name, _symbol, _lzEndpoint, _delegate) Ownable(_delegate) Pausable() {}

    /// @notice Checks if an address is blacklisted
    /// @param _account The address to check
    /// @return bool True if the address is blacklisted, false otherwise
    function isUserBlacklisted(address _account) public view returns (bool) {
        return isBlacklisted[_account];
    }

    /// @notice Internal function to update token balances with blacklist checks
    /// @dev Overrides the _update function to include blacklist validation
    /// @param from The sender's address
    /// @param to The recipient's address
    /// @param value The amount of tokens to transfer
    function _update(address from, address to, uint256 value) internal override whenNotPaused {
        if (isUserBlacklisted(from)) {
            revert UserBlacklisted(from);
        }
        if (isUserBlacklisted(to)) {
            revert UserBlacklisted(to);
        }
        super._update(from, to, value);
    }

    /// @notice Internal function to approve token allowances with blacklist checks
    /// @dev Overrides the _approve function to include blacklist validation
    /// @param owner The address of the token owner
    /// @param spender The address allowed to spend the tokens
    /// @param value The amount of tokens to approve
    /// @param emitEvent Whether to emit an approval event
    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal override whenNotPaused {
        if (isUserBlacklisted(owner)) {
            revert UserBlacklisted(owner);
        }
        if (isUserBlacklisted(spender)) {
            revert UserBlacklisted(spender);
        }
        super._approve(owner, spender, value, emitEvent);
    }

    /// @notice Pauses all token transfers
    /// @dev Only callable by the contract owner
    function pause() public onlyOwner {
        _pause();
    }

    /// @notice Unpauses token transfers
    /// @dev Only callable by the contract owner
    function unpause() public onlyOwner {
        _unpause();
    }

    /// @notice Issues new tokens to a specified address
    /// @dev Only callable by the contract owner
    /// @param _to The address to receive the new tokens
    /// @param _amount The amount of tokens to issue
    function issue(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    /// @notice Adds an address to the blacklist
    /// @dev Only callable by the contract owner
    /// @param _account The address to blacklist
    function addToBlacklist(address _account) public onlyOwner {
        isBlacklisted[_account] = true;
        emit Blacklisted(_account);
    }

    /// @notice Removes an address from the blacklist
    /// @dev Only callable by the contract owner
    /// @param _account The address to remove from the blacklist
    function removeFromBlacklist(address _account) public onlyOwner {
        isBlacklisted[_account] = false;
        emit Unblacklisted(_account);
    }
}
