// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {INDSale, IINDMintable} from "../contracts/INDSale.sol";
import {PriceCurve} from "../contracts/lib/PriceCurve.sol";

contract MockIND is IINDMintable {
    uint256 public override totalSupply;

    address public lastTo;
    uint256 public lastAmount;
    uint64 public lastMantissa;
    bytes32 public lastCharacteristic;

    function mintWithMantissa(
        address to,
        uint256 amount,
        uint64 mantissaSeconds,
        bytes32 characteristic
    ) external override returns (bool) {
        totalSupply += amount;
        lastTo = to;
        lastAmount = amount;
        lastMantissa = mantissaSeconds;
        lastCharacteristic = characteristic;
        return true;
    }
}

contract INDSaleTest is Test {
    MockIND internal ind;
    INDSale internal sale;

    address internal admin = address(0xA11CE);
    address internal buyer = address(0xB0B);
    address internal recipient = address(0xCAFE);

    uint64 internal constant MIN_MANTISSA_SECONDS = 1 days;
    address payable internal constant ETH_BURN_SINK =
        payable(0x000000000000000000000000000000000000dEaD);

    function setUp() public {
        ind = new MockIND();
        sale = new INDSale(admin, IINDMintable(address(ind)));
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
        assertEq(ind.lastMantissa(), MIN_MANTISSA_SECONDS, "mantissa mismatch");
        assertEq(ind.lastCharacteristic(), bytes32(0), "characteristic mismatch");

        assertEq(burnAfter - burnBefore, expectedUsed, "burned ETH mismatch");
        assertEq(buyerBefore - buyerAfter, expectedUsed, "buyer net spend mismatch");
        assertEq(ethIn - (buyerBefore - buyerAfter), expectedRefund, "refund mismatch");
    }

    function test_buyTo_mints_to_recipient() public {
        uint256 ethIn = 1 ether;
        bytes32 characteristic = keccak256("IND-LOT");

        vm.prank(buyer);
        uint256 outWei = sale.buyTo{value: ethIn}(recipient, 0, MIN_MANTISSA_SECONDS, characteristic);

        assertGt(outWei, 0, "out=0");
        assertEq(ind.lastTo(), recipient, "wrong recipient");
        assertEq(ind.lastAmount(), outWei, "wrong amount");
        assertEq(ind.lastMantissa(), MIN_MANTISSA_SECONDS, "wrong mantissa");
        assertEq(ind.lastCharacteristic(), characteristic, "wrong characteristic");
    }

    function test_buy_reverts_zero_value() public {
        vm.prank(buyer);
        vm.expectRevert(INDSale.ZeroValue.selector);
        sale.buy{value: 0}(0);
    }

    function test_buyTo_reverts_zero_recipient() public {
        vm.prank(buyer);
        vm.expectRevert(INDSale.ZeroRecipient.selector);
        sale.buyTo{value: 1 ether}(address(0), 0, MIN_MANTISSA_SECONDS, bytes32(0));
    }

    function test_buyTo_reverts_invalid_mantissa() public {
        vm.prank(buyer);
        vm.expectRevert(INDSale.InvalidMantissa.selector);
        sale.buyTo{value: 1 ether}(recipient, 0, MIN_MANTISSA_SECONDS - 1, bytes32(0));
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

    function test_receive_reverts() public {
        vm.prank(buyer);
        vm.expectRevert(bytes("use buy"));
        (bool ok, ) = address(sale).call{value: 1 ether}("");
        ok;
    }

    function test_fallback_reverts() public {
        vm.prank(buyer);
        vm.expectRevert(bytes("use buy"));
        (bool ok, ) = address(sale).call{value: 1 ether}(hex"1234");
        ok;
    }
}
