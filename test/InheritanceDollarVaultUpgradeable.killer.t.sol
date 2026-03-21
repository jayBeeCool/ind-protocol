// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InheritanceDollarVaultUpgradeable} from "../contracts/InheritanceDollarVaultUpgradeable.sol";
import {MockINDKeyRegistryLite} from "./mocks/MockINDKeyRegistryLite.sol";

contract InheritanceDollarVaultUpgradeableKillerTest is Test {
    InheritanceDollarVaultUpgradeable internal ind;
    MockINDKeyRegistryLite internal reg;

    address internal admin = address(0xA11CE);
    address internal sale = address(0x5A1E);

    address internal alice = address(0xAAA1);
    address internal bob = address(0xBBB2);
    address internal carol = address(0xCCC3);
    address internal signing = address(0x1111);

    uint256 internal constant MAX_SUPPLY = 100_000_000_000 ether;

    function setUp() external {
        reg = new MockINDKeyRegistryLite();
        InheritanceDollarVaultUpgradeable impl = new InheritanceDollarVaultUpgradeable();

        bytes memory initData =
            abi.encodeCall(InheritanceDollarVaultUpgradeable.initialize, (admin, MAX_SUPPLY, address(reg)));

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        ind = InheritanceDollarVaultUpgradeable(address(proxy));

        vm.startPrank(admin);
        ind.grantRole(ind.MINTER_ROLE(), sale);
        vm.stopPrank();

        vm.startPrank(sale);
        ind.mint(alice, 100 ether);
        ind.mint(bob, 100 ether);
        vm.stopPrank();
    }

    function test_killer_total_balance_invariant() external {
        vm.startPrank(alice);
        assertTrue(ind.protect(60 ether));
        assertTrue(ind.unprotect(10 ether));
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        assertTrue(ind.transfer(bob, 20 ether));
        vm.stopPrank();

        assertEq(ind.balanceOf(alice), ind.unprotectedBalanceOf(alice) + ind.protectedBalanceOf(alice));
        assertEq(ind.balanceOf(bob), ind.unprotectedBalanceOf(bob) + ind.protectedBalanceOf(bob));
    }

    function test_killer_redirect_protected_inheritance() external {
        reg.setOwnerKeys(carol, signing);

        vm.prank(alice);
        assertTrue(ind.protect(50 ether));

        vm.prank(alice);
        assertTrue(ind.transferWithInheritance(carol, 30 ether, uint64(1 days), bytes32(0)));

        assertEq(ind.protectedBalanceOf(carol), 0);
        assertEq(ind.protectedBalanceOf(signing), 30 ether);
    }

    function test_killer_signing_identity_consistency() external {
        reg.setOwnerKeys(alice, signing);

        vm.prank(sale);
        ind.mint(signing, 10 ether);

        uint64 beforeTs = ind.lastInteractionOf(alice);

        vm.warp(block.timestamp + 100);

        vm.prank(signing);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        assertTrue(ind.transfer(bob, 1 ether));

        uint64 afterTs = ind.lastInteractionOf(alice);
        assertGt(afterTs, beforeTs);
    }

    function test_killer_no_bypass_protected_via_transferFrom() external {
        vm.prank(alice);
        assertTrue(ind.protect(80 ether));

        vm.prank(alice);
        assertTrue(ind.approve(bob, 50 ether));

        vm.prank(bob);
        vm.expectRevert(InheritanceDollarVaultUpgradeable.InsufficientUnprotectedBalance.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ind.transferFrom(alice, carol, 50 ether);
    }

    function test_killer_full_system_stress() external {
        reg.setOwnerKeys(carol, signing);

        vm.startPrank(alice);
        assertTrue(ind.protect(70 ether));
        assertTrue(ind.unprotect(20 ether));
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        assertTrue(ind.transfer(bob, 10 ether));
        assertTrue(ind.transferWithInheritance(carol, 30 ether, uint64(1 days), bytes32(0)));
        vm.stopPrank();

        assertEq(ind.balanceOf(alice), ind.unprotectedBalanceOf(alice) + ind.protectedBalanceOf(alice));
        assertEq(ind.balanceOf(signing), ind.unprotectedBalanceOf(signing) + ind.protectedBalanceOf(signing));
        assertEq(ind.protectedBalanceOf(carol), 0);
        assertGt(ind.protectedBalanceOf(signing), 0);
    }
}
