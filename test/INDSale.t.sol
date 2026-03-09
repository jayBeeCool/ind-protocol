// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {INDSale} from "../contracts/INDSale.sol";
import {PriceCurve} from "../contracts/lib/PriceCurve.sol";

contract MockIND {
    uint256 public totalSupply;

    address public lastTo;
    uint256 public lastAmount;

    function mintWithMantissa(
        address to,
        uint256 amount,
        uint64,
        bytes32
    ) external returns (bool) {
        totalSupply += amount;
        lastTo = to;
        lastAmount = amount;
        return true;
    }
}

contract INDSaleTest is Test {
    MockIND internal ind;
    INDSale internal sale;

    address internal admin = address(0xA11CE);
    address internal buyer = address(0xB0B);
    address internal recipient = address(0xCAFE);

    address payable internal constant ETH_BURN_SINK =
        payable(0x000000000000000000000000000000000000dEaD);

    function setUp() public {
        ind = new MockIND();
        sale = new INDSale(admin, address(ind));
        vm.deal(buyer, 100 ether);
    }

    function test_buy_mints_and_burns_and_refunds() public {
        uint256 ethIn = 1 ether;

        uint256 expectedOut = PriceCurve.quoteBuy(ind.totalSupply(), ethIn);
        assertGt(expectedOut, 0, "expectedOut=0");

        uint256 expectedUsed = PriceCurve.costToMint(ind.totalSupply(), expectedOut);
        uint256 expectedRefund = ethIn - expectedUsed;

        uint256 burnBefore = ETH_BURN_SINK.balance;
        uint256 buyerBefore = buyer.balance;

        vm.prank(buyer);
        uint256 outWei = sale.buy{value: ethIn}(0);

        uint256 burnAfter = ETH_BURN_SINK.balance;
        uint256 buyerAfter = buyer.balance;

        assertEq(outWei, expectedOut, "out mismatch");
        assertEq(ind.totalSupply(), expectedOut, "supply mismatch");
        assertEq(ind.lastTo(), buyer, "recipient mismatch");
        assertEq(ind.lastAmount(), expectedOut, "mint amount mismatch");

        assertEq(burnAfter - burnBefore, expectedUsed, "burned ETH mismatch");
        assertEq(buyerBefore - buyerAfter, expectedUsed, "buyer net spend mismatch");
        assertEq(ethIn - (buyerBefore - buyerAfter), expectedRefund, "refund mismatch");
    }

    function test_buyTo_mints_to_recipient() public {
        uint256 ethIn = 1 ether;

        vm.prank(buyer);
        uint256 outWei = sale.buyTo{value: ethIn}(recipient, 0);

        assertGt(outWei, 0, "out=0");
        assertEq(ind.lastTo(), recipient, "wrong recipient");
        assertEq(ind.lastAmount(), outWei, "wrong amount");
    }

    function test_purchaseFor_custom_refund_to() public {
        uint256 ethIn = 1 ether;
        address refundTo = address(0xD00D);
        vm.deal(refundTo, 0);

        uint256 expectedOut = PriceCurve.quoteBuy(ind.totalSupply(), ethIn);
        uint256 expectedUsed = PriceCurve.costToMint(ind.totalSupply(), expectedOut);
        uint256 expectedRefund = ethIn - expectedUsed;

        uint256 refundBefore = refundTo.balance;

        vm.prank(buyer);
        uint256 outWei = sale.purchaseFor{value: ethIn}(recipient, refundTo, 0);

        assertEq(outWei, expectedOut, "out mismatch");
        assertEq(ind.lastTo(), recipient, "wrong recipient");
        assertEq(refundTo.balance - refundBefore, expectedRefund, "wrong refund");
    }

    function test_buy_reverts_zero_value() public {
        vm.prank(buyer);
        vm.expectRevert(INDSale.ZeroValue.selector);
        sale.buy{value: 0}(0);
    }

    function test_buyTo_reverts_zero_recipient() public {
        vm.prank(buyer);
        vm.expectRevert(INDSale.ZeroRecipient.selector);
        sale.buyTo{value: 1 ether}(address(0), 0);
    }

    function test_purchaseFor_reverts_zero_refund_to() public {
        vm.prank(buyer);
        vm.expectRevert(INDSale.ZeroRefundTo.selector);
        sale.purchaseFor{value: 1 ether}(recipient, address(0), 0);
    }

    function test_buy_reverts_zero_output() public {
        vm.prank(buyer);
        vm.expectRevert(INDSale.ZeroValue.selector);
        sale.buy{value: 0}(0);
    }

    function test_buy_reverts_on_slippage() public {
        uint256 ethIn = 1 ether;
        uint256 expectedOut = PriceCurve.quoteBuy(ind.totalSupply(), ethIn);
        assertGt(expectedOut, 0, "expectedOut=0");

        vm.prank(buyer);
        vm.expectRevert(INDSale.SlippageTooHigh.selector);
        sale.buy{value: ethIn}(expectedOut + 1);
    }

    function test_fallback_reverts() public {
        vm.prank(buyer);
        vm.expectRevert(bytes("use buy"));
        (bool ok, ) = address(sale).call{value: 1 ether}(hex"1234");
        ok;
    }

    function test_receive_reverts() public {
        vm.prank(buyer);
        vm.expectRevert(bytes("use buy"));
        (bool ok, ) = address(sale).call{value: 1 ether}("");
        ok;
    }
}
