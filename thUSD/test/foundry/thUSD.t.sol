// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { thUSD } from "../../contracts/thUSD.sol";

// OApp imports
import { IOAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

// OFT imports
import { IOFT, SendParam, OFTReceipt } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { MessagingFee, MessagingReceipt } from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";
import { OFTMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";

// OZ imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Forge imports
import "forge-std/console.sol";

// DevTools imports
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

contract MyOFTTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 private eid = 1;
    thUSD private thUSDtkn;

    error UserBlacklisted(address user);

    address private userA = makeAddr("userA");
    address private userB = makeAddr("userB");
    uint256 private initialBalance = 100 ether;

    function setUp() public virtual override {
        vm.deal(userA, 1000 ether);
        vm.deal(userB, 1000 ether);

        super.setUp();
        setUpEndpoints(1, LibraryType.UltraLightNode);

        thUSDtkn = thUSD(
            _deployOApp(type(thUSD).creationCode, abi.encode("thUSD", "thUSD", address(endpoints[eid]), address(this)))
        );

        // config and wire the oft
        address[] memory ofts = new address[](1);
        ofts[0] = address(thUSDtkn);
        this.wireOApps(ofts);

        // mint tokens
        thUSDtkn.issue(userA, initialBalance);
        thUSDtkn.issue(userB, initialBalance);
    }

    function test_constructor() public view {
        assertEq(thUSDtkn.owner(), address(this));

        assertEq(thUSDtkn.balanceOf(userA), initialBalance);
        assertEq(thUSDtkn.balanceOf(userB), initialBalance);

        assertEq(thUSDtkn.token(), address(thUSDtkn));
    }

    function test_transfer() public {
        uint256 tokensToSend = 1 ether;

        assertEq(thUSDtkn.balanceOf(userA), initialBalance);
        assertEq(thUSDtkn.balanceOf(userB), initialBalance);

        vm.prank(userA);
        thUSDtkn.transfer(userB, tokensToSend);

        assertEq(thUSDtkn.balanceOf(userA), initialBalance - tokensToSend);
        assertEq(thUSDtkn.balanceOf(userB), initialBalance + tokensToSend);
    }

    function test_owner_can_mint() public {
        vm.prank(address(this));
        thUSDtkn.issue(userA, 1 ether);

        assertEq(thUSDtkn.balanceOf(userA), initialBalance + 1 ether);
    }

    function test_transfer_ownership() public {
        vm.prank(address(this));
        thUSDtkn.transferOwnership(userA);

        assertEq(thUSDtkn.owner(), userA);
    }

    function test_approve() public {
        vm.prank(userA);
        thUSDtkn.approve(userB, 1 ether);

        assertEq(thUSDtkn.allowance(userA, userB), 1 ether);
    }

    function test_blacklist() public {
        vm.prank(address(this));
        thUSDtkn.addToBlacklist(userA);

        assertEq(thUSDtkn.isUserBlacklisted(userA), true);

        vm.prank(address(this));
        thUSDtkn.removeFromBlacklist(userA);

        assertEq(thUSDtkn.isUserBlacklisted(userA), false);
    }

    function test_blacklist_transfer() public {
        vm.prank(address(this));
        thUSDtkn.addToBlacklist(userA);

        vm.prank(userA);
        vm.expectPartialRevert(UserBlacklisted.selector);
        thUSDtkn.transfer(userB, 1);
    }

    function test_blacklist_approve() public {
        vm.prank(address(this));
        thUSDtkn.addToBlacklist(userA);

        vm.prank(userA);
        vm.expectPartialRevert(UserBlacklisted.selector);
        thUSDtkn.approve(userB, 1);
    }
}
