// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/*
▗▄▄▄▖▗▖ ▗▖ ▗▄▖ ▗▄▄▖ ▗▖ ▗▖ ▗▄▖ 
  █  ▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌
  █  ▐▛▀▜▌▐▛▀▜▌▐▛▀▚▖▐▌ ▐▌▐▛▀▜▌
  █  ▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▙█▟▌▐▌ ▐▌


visit : https://tharwa.finance                         
*/

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract TharwaWrapper is ERC4626, Ownable {
    using SafeERC20 for IERC20;

    // Address of the underlying asset (the unwrapped version)
    IERC20 internal immutable ASSET;

    constructor(IERC20 _underlyingToken, string memory _name, string memory _symbol)
        ERC4626(_underlyingToken)
        ERC20(_name, _symbol)
        Ownable(msg.sender)
    {
        ASSET = _underlyingToken;
    }

    ///////////////////////////// ERC4626 compliancy /////////////////////////////

    function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {
        return _wrap(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
        return _wrap(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address sharesOwner)
        public
        virtual
        override
        returns (uint256)
    {
        return _unwrap(assets, receiver, sharesOwner);
    }

    function redeem(uint256 shares, address receiver, address sharesOwner) public virtual override returns (uint256) {
        return _unwrap(shares, receiver, sharesOwner);
    }

    /// @notice Rescue ERC20 tokens mistakenly sent to this contract
    /// @dev If the underlying asset is attempted, only the non-backed amount can be rescued
    function rescueErc20Token(IERC20 token, uint256 amount, address receiver) external onlyOwner {
        if (address(token) == address(ASSET)) {
            uint256 maxRescue = ASSET.balanceOf(address(this)) - totalSupply();
            require(amount <= maxRescue, "Rescue amount to high");
        }
        token.safeTransfer(receiver, amount);
    }

    ///////////////////////////// view functions /////////////////////////////

    function convertToShares(uint256 assets) public view virtual override returns (uint256) {
        return assets;
    }

    function convertToAssets(uint256 shares) public view virtual override returns (uint256) {
        return shares;
    }

    function previewDeposit(uint256 assets) public view virtual override returns (uint256) {
        return assets;
    }

    function previewMint(uint256 shares) public view virtual override returns (uint256) {
        return shares;
    }

    function previewWithdraw(uint256 assets) public view virtual override returns (uint256) {
        return assets;
    }

    function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
        return shares;
    }

    //////////////////////////  internal functions /////////////////////////////

    function _wrap(uint256 amount, address receiver) internal returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (amount > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, amount, maxAssets);
        }

        ASSET.safeTransferFrom(msg.sender, address(this), amount);
        _mint(receiver, amount);

        emit Deposit(msg.sender, receiver, amount, amount);
        return amount;
    }

    function _unwrap(uint256 amount, address receiver, address sharesOwner) internal returns (uint256) {
        if (msg.sender != sharesOwner) {
            _spendAllowance(sharesOwner, msg.sender, amount);
        }

        _burn(sharesOwner, amount);
        ASSET.safeTransfer(receiver, amount);

        emit Withdraw(msg.sender, receiver, sharesOwner, amount, amount);
        return amount;
    }
}
