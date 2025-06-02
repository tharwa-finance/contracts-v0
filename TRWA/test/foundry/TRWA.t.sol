// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { TRWA } from "../../contracts/TRWA.sol";

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
import { console2 } from "forge-std/console2.sol";

// DevTools imports
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

interface IUniswapV2Router02 {
    function WETH() external pure returns (address);

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;

    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);

    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);
}

contract MyOFTTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 private eid = 1;

    TRWA private trwa;

    address private userA = makeAddr("userA");
    address private userB = makeAddr("userB");
    uint256 private initialBalance = 100 ether;
    address private tokenTreasury = address(0x1337);

    function setUp() public virtual override {
        vm.deal(userA, 1000 ether);
        vm.deal(userB, 1000 ether);

        vm.createSelectFork("https://rpc.payload.de");

        super.setUp();
        setUpEndpoints(1, LibraryType.UltraLightNode);

        trwa = TRWA(
            _deployOApp(
                type(TRWA).creationCode,
                abi.encode("TRWA", "TRWA", address(endpoints[eid]), address(this), tokenTreasury)
            )
        );

        // config and wire the oft
        address[] memory ofts = new address[](1);
        ofts[0] = address(trwa);
        this.wireOApps(ofts);
    }

    function test_constructor() public view {
        assertEq(trwa.owner(), address(this));
    }

    function treasury_initial_balance() public view {
        assertEq(trwa.balanceOf(tokenTreasury), (trwa.MAX_SUPPLY() * 20) / 100);
    }

    function test_open_trading() public {
        vm.prank(trwa.owner());
        vm.deal(trwa.owner(), 1 ether);
        trwa.openTrading{ value: 1 ether }();
    }

    function test_buy_tax_is_enforced() public {
        uint256 tokensToSend = 1 ether;

        // Open trading first with ETH to create the pair
        vm.prank(trwa.owner());
        vm.deal(trwa.owner(), 1 ether);
        trwa.openTrading{ value: 1 ether }();

        // Get the created pair address
        address pairAddress = trwa.pair();

        // Fund the pair with additional tokens to simulate a buy
        vm.prank(tokenTreasury);
        trwa.transfer(pairAddress, tokensToSend);

        // Now simulate a buy: pair -> userA
        vm.prank(pairAddress);
        trwa.transfer(userA, tokensToSend);

        uint256 expectedTax = (tokensToSend * trwa.buyTaxBps()) / 10_000;

        // Check user received tokens minus tax
        assertEq(trwa.balanceOf(userA), tokensToSend - expectedTax);

        // Check treasury received the tax
        // Initial treasury balance was 20% of MAX_SUPPLY
        uint256 initialTreasuryBalance = (trwa.MAX_SUPPLY() * 20) / 100;
        assertEq(trwa.balanceOf(trwa.treasury()), initialTreasuryBalance - tokensToSend + expectedTax);
    }

    function test_sell_tax_is_enforced() public {
        uint256 tokensToSend = 1 ether;

        // Open trading first with ETH to create the pair
        vm.prank(trwa.owner());
        vm.deal(trwa.owner(), 1 ether);
        trwa.openTrading{ value: 1 ether }();

        // Get the created pair address
        address pairAddress = trwa.pair();

        // Get the initial balance of the pair (from liquidity addition)
        uint256 initialPairBalance = trwa.balanceOf(pairAddress);

        // Give userA some tokens to sell
        vm.prank(tokenTreasury);
        trwa.transfer(userA, tokensToSend);

        // Now simulate a sell: userA -> pair
        vm.prank(userA);
        trwa.transfer(pairAddress, tokensToSend);

        uint256 expectedTax = (tokensToSend * trwa.sellTaxBps()) / 10_000;

        // Check pair received tokens minus tax (plus initial balance)
        assertEq(trwa.balanceOf(pairAddress), initialPairBalance + tokensToSend - expectedTax);

        // Check treasury received the tax
        // Initial treasury balance was 20% of MAX_SUPPLY minus the tokens sent to userA
        uint256 initialTreasuryBalance = (trwa.MAX_SUPPLY() * 20) / 100;
        assertEq(trwa.balanceOf(trwa.treasury()), initialTreasuryBalance - tokensToSend + expectedTax);
    }

    function test_swapETHForExactTokens_is_working() public {
        // First, open trading to create the liquidity pool
        vm.prank(trwa.owner());
        vm.deal(trwa.owner(), 10 ether);
        trwa.openTrading{ value: 10 ether }();

        // Setup Uniswap router
        IUniswapV2Router02 router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

        // Create path: WETH -> TRWA
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(trwa);

        // Fund userA with ETH
        vm.deal(userA, 1 ether);

        // Get initial balances
        uint256 initialUserBalance = trwa.balanceOf(userA);
        uint256 initialTreasuryBalance = trwa.balanceOf(trwa.treasury());

        uint256 ethToSwap = 0.1 ether;

        // Execute swap as userA
        vm.prank(userA);
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{ value: ethToSwap }(
            0, // Accept any amount of tokens
            path,
            userA,
            block.timestamp + 300 // 5 minutes deadline
        );

        // Get final balances
        uint256 finalUserBalance = trwa.balanceOf(userA);
        uint256 finalTreasuryBalance = trwa.balanceOf(trwa.treasury());

        // Calculate tokens received and tax paid
        uint256 tokensReceived = finalUserBalance - initialUserBalance;
        uint256 taxPaid = finalTreasuryBalance - initialTreasuryBalance;

        // Verify user received tokens
        assertGt(tokensReceived, 0, "User should have received tokens");

        // Verify tax was collected (should be 5% of the gross amount)
        // Tax = tokensReceived * buyTaxBps / (10000 - buyTaxBps)
        uint256 expectedTax = (tokensReceived * trwa.buyTaxBps()) / (10000 - trwa.buyTaxBps());

        // Allow for small rounding differences (within 1%)
        assertApproxEqRel(taxPaid, expectedTax, 0.01e18, "Tax amount should match expected");

        // console2.log("ETH swapped:", ethToSwap);
        // console2.log("Tokens received by user:", tokensReceived);
        // console2.log("Tax paid to treasury:", taxPaid);
        // console2.log("Effective tax rate:", (taxPaid * 10000) / (tokensReceived + taxPaid), "bps");
    }

    function test_transfer() public {
        uint256 tokensToSend = 1 ether;

        vm.prank(tokenTreasury);
        trwa.transfer(userA, tokensToSend);

        assertEq(trwa.balanceOf(userA), tokensToSend);
    }

    function test_set_taxes() public {
        vm.prank(trwa.owner());
        trwa.setTaxes(500, 500);

        assertEq(trwa.buyTaxBps(), 500);
        assertEq(trwa.sellTaxBps(), 500);
    }

    function test_transfer_ownership() public {
        vm.prank(address(this));
        trwa.transferOwnership(userA);

        assertEq(trwa.owner(), userA);
    }

    function test_pause() public {
        vm.prank(address(this));
        trwa.pause();

        assertEq(trwa.paused(), true);
    }

    function test_can_not_transfer_when_paused() public {
        vm.prank(address(this));
        trwa.pause();

        vm.prank(tokenTreasury);
        vm.expectRevert();
        trwa.transfer(userA, 1 ether);
    }
}
