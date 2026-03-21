// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InheritanceDollarVaultUpgradeable} from "../contracts/InheritanceDollarVaultUpgradeable.sol";
import {MockINDKeyRegistryLite} from "./mocks/MockINDKeyRegistryLite.sol";

contract Block2LotsTest is Test {
    InheritanceDollarVaultUpgradeable ind;
    MockINDKeyRegistryLite reg;

    address admin = address(1);
    address sale = address(2);
    address alice = address(3);
    address bob = address(4);

    function setUp() external {
        reg = new MockINDKeyRegistryLite();
        InheritanceDollarVaultUpgradeable impl = new InheritanceDollarVaultUpgradeable();

        bytes memory init = abi.encodeCall(InheritanceDollarVaultUpgradeable.initialize, (admin, 1e30, address(reg)));

        ind = InheritanceDollarVaultUpgradeable(address(new ERC1967Proxy(address(impl), init)));

        vm.startPrank(admin);
        ind.grantRole(ind.MINTER_ROLE(), sale);
        vm.stopPrank();

        vm.prank(sale);
        ind.mint(alice, 100 ether);
    }

    function test_protect_creates_lot() external {
        vm.prank(alice);
        ind.protect(50 ether);

        assertEq(ind.protectedBalanceOf(alice), 50 ether);
    }

    function test_transferWithInheritance_creates_locked_lot() external {
        vm.prank(alice);
        ind.protect(50 ether);

        vm.prank(alice);
        ind.transferWithInheritance(bob, 20 ether, 1 days, bytes32(0));

        assertEq(ind.lockedBalanceOf(bob), 20 ether);
    }

    function test_spendable_after_unlock() external {
        vm.prank(alice);
        ind.protect(50 ether);

        vm.prank(alice);
        ind.transferWithInheritance(bob, 20 ether, 1 days, bytes32(0));

        vm.warp(block.timestamp + 1 days + 1);

        assertEq(ind.spendableBalanceOf(bob), 20 ether);
    }

    function test_consume_lots_fifo() external {
        vm.prank(alice);
        ind.protect(50 ether);

        vm.prank(alice);
        ind.transferWithInheritance(alice, 20 ether, 1 days, bytes32(0));

        vm.warp(block.timestamp + 2 days);

        vm.prank(alice);
        ind.transferWithInheritance(bob, 20 ether, 1 days, bytes32(0));

        assertEq(ind.protectedBalanceOf(alice), 30 ether);
    }
}
