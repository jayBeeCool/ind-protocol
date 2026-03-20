// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {INDSale} from "../contracts/INDSale.sol";
import {INDDepositReceiver} from "../contracts/INDDepositReceiver.sol";
import {PriceCurve} from "../contracts/lib/PriceCurve.sol";

contract MockINDForReceiver {
    uint256 public totalSupply;

    address public lastTo;
    uint256 public lastAmount;

    function mintWithMantissa(address to, uint256 amount, uint64, bytes32) external returns (bool) {
        totalSupply += amount;
        lastTo = to;
        lastAmount = amount;
        return true;
    }
}

contract INDDepositReceiverTest is Test {
    MockINDForReceiver internal ind;
    INDSale internal sale;
    INDDepositReceiver internal receiver;

    address internal admin = address(0xA11CE);
    address internal buyer = address(0xB0B);
    address internal recipient = address(0xCAFE);

    address payable internal constant ETH_BURN_SINK = payable(0x000000000000000000000000000000000000dEaD);

    function setUp() public {
        ind = new MockINDForReceiver();
        sale = new INDSale(admin, address(ind));
        receiver = new INDDepositReceiver(address(sale), recipient);
        vm.deal(buyer, 100 ether);
    }

    function test_plain_eth_send_to_receiver_mints_to_bound_recipient() public {
        uint256 ethIn = 1 ether;
        uint256 expectedOut = PriceCurve.quoteBuy(ind.totalSupply(), ethIn);
        uint256 expectedUsed = PriceCurve.costToMint(ind.totalSupply(), expectedOut);
        uint256 burnBefore = ETH_BURN_SINK.balance;

        vm.prank(buyer);
        (bool ok,) = address(receiver).call{value: ethIn}("");
        assertTrue(ok, "plain send failed");

        assertEq(ind.lastTo(), recipient, "recipient mismatch");
        assertEq(ind.lastAmount(), expectedOut, "amount mismatch");
        assertEq(ind.totalSupply(), expectedOut, "supply mismatch");
        assertEq(ETH_BURN_SINK.balance - burnBefore, expectedUsed, "burn mismatch");
    }

    function test_receiver_deposit_function_works() public {
        uint256 ethIn = 1 ether;

        vm.prank(buyer);
        uint256 outWei = receiver.deposit{value: ethIn}(0);

        assertGt(outWei, 0, "out=0");
        assertEq(ind.lastTo(), recipient, "recipient mismatch");
        assertEq(ind.lastAmount(), outWei, "amount mismatch");
    }
}
