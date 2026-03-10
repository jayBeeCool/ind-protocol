// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/INDReceiverV2.sol";
import "../contracts/INDReceiverV3.sol";
import "../contracts/INDReceiverV4.sol";

contract MockSale {
    enum Method {
        None,
        PurchaseFor,
        BuyTo
    }

    Method public lastMethod;
    address public lastRecipient;
    address public lastRefundTo;
    uint256 public lastMinOutWei;
    uint256 public lastValue;

    function purchaseFor(address recipient, address refundTo) external payable {
        lastMethod = Method.PurchaseFor;
        lastRecipient = recipient;
        lastRefundTo = refundTo;
        lastMinOutWei = 0;
        lastValue = msg.value;
    }

    function buyTo(address recipient, uint256 minOutWei) external payable {
        lastMethod = Method.BuyTo;
        lastRecipient = recipient;
        lastRefundTo = address(0);
        lastMinOutWei = minOutWei;
        lastValue = msg.value;
    }
}

contract INDReceiverVariantsTest is Test {
    MockSale internal sale;
    INDReceiverV2 internal v2;
    INDReceiverV3 internal v3;
    INDReceiverV4 internal v4;

    address internal user = address(0x1111);
    address internal other = address(0x2222);

    function setUp() external {
        sale = new MockSale();
        v2 = new INDReceiverV2(address(sale));
        v3 = new INDReceiverV3(address(sale));
        v4 = new INDReceiverV4(address(sale));
        vm.deal(user, 10 ether);
    }

    function testV2_buy_forwardsToPurchaseFor() external {
        vm.prank(user);
        v2.buy{value: 0.001 ether}();

        assertEq(uint256(sale.lastMethod()), uint256(MockSale.Method.PurchaseFor));
        assertEq(sale.lastRecipient(), user);
        assertEq(sale.lastRefundTo(), user);
        assertEq(sale.lastValue(), 0.001 ether);
    }

    function testV2_receive_forwardsToPurchaseFor() external {
        vm.prank(user);
        (bool ok,) = address(v2).call{value: 0.002 ether}("");
        assertTrue(ok);

        assertEq(uint256(sale.lastMethod()), uint256(MockSale.Method.PurchaseFor));
        assertEq(sale.lastRecipient(), user);
        assertEq(sale.lastRefundTo(), user);
        assertEq(sale.lastValue(), 0.002 ether);
    }

    function testV3_buy_forwardsToBuyToWithMinOut() external {
        vm.prank(user);
        v3.buy{value: 0.003 ether}(12345);

        assertEq(uint256(sale.lastMethod()), uint256(MockSale.Method.BuyTo));
        assertEq(sale.lastRecipient(), user);
        assertEq(sale.lastMinOutWei(), 12345);
        assertEq(sale.lastValue(), 0.003 ether);
    }

    function testV3_receive_usesZeroMinOut() external {
        vm.prank(user);
        (bool ok,) = address(v3).call{value: 0.004 ether}("");
        assertTrue(ok);

        assertEq(uint256(sale.lastMethod()), uint256(MockSale.Method.BuyTo));
        assertEq(sale.lastRecipient(), user);
        assertEq(sale.lastMinOutWei(), 0);
        assertEq(sale.lastValue(), 0.004 ether);
    }

    function testV4_buy_forwardsRecipientAndMinOut() external {
        vm.prank(user);
        v4.buy{value: 0.005 ether}(other, 777);

        assertEq(uint256(sale.lastMethod()), uint256(MockSale.Method.BuyTo));
        assertEq(sale.lastRecipient(), other);
        assertEq(sale.lastMinOutWei(), 777);
        assertEq(sale.lastValue(), 0.005 ether);
    }

    function testV4_receive_usesSenderAndZeroMinOut() external {
        vm.prank(user);
        (bool ok,) = address(v4).call{value: 0.006 ether}("");
        assertTrue(ok);

        assertEq(uint256(sale.lastMethod()), uint256(MockSale.Method.BuyTo));
        assertEq(sale.lastRecipient(), user);
        assertEq(sale.lastMinOutWei(), 0);
        assertEq(sale.lastValue(), 0.006 ether);
    }

    function testV4_buy_revertsOnZeroRecipient() external {
        vm.prank(user);
        vm.expectRevert(INDReceiverV4.ZeroRecipient.selector);
        v4.buy{value: 0.001 ether}(address(0), 1);
    }
}
