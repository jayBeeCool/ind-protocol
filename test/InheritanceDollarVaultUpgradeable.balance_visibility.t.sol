// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InheritanceDollarVaultUpgradeable} from "../contracts/InheritanceDollarVaultUpgradeable.sol";
import {MockINDKeyRegistryLite} from "./mocks/MockINDKeyRegistryLite.sol";

contract InheritanceDollarVaultUpgradeableBalanceVisibilityTest is Test {
    InheritanceDollarVaultUpgradeable internal ind;
    MockINDKeyRegistryLite internal reg;

    address internal admin = address(0xA11CE);
    address internal sale = address(0x5A1E);
    address internal alice = address(0xAAA1);
    address internal bob = address(0xBBB2);

    uint256 internal constant MAX_SUPPLY = 100_000_000_000 ether;

    function setUp() external {
        reg = new MockINDKeyRegistryLite();
        reg.unsafeSetProtectedAwareNoRedirect(bob);

        InheritanceDollarVaultUpgradeable impl = new InheritanceDollarVaultUpgradeable();

        bytes memory initData =
            abi.encodeCall(InheritanceDollarVaultUpgradeable.initialize, (admin, MAX_SUPPLY, address(reg)));

        ind = InheritanceDollarVaultUpgradeable(address(new ERC1967Proxy(address(impl), initData)));

        vm.startPrank(admin);
        ind.grantRole(ind.MINTER_ROLE(), sale);
        vm.stopPrank();

        vm.prank(sale);
        ind.mint(alice, 100 ether);
    }

    function test_balanceOf_excludes_locked_protected_and_totalBalance_includes_it() external {
        vm.startPrank(alice);
        ind.protect(50 ether);
        ind.transferWithInheritance(bob, 20 ether, uint64(1 days), bytes32(0));
        vm.stopPrank();

        assertEq(ind.unprotectedBalanceOf(bob), 0);
        assertEq(ind.lockedBalanceOf(bob), 20 ether);
        assertEq(ind.spendableBalanceOf(bob), 0);
        assertEq(ind.protectedBalanceOf(bob), 20 ether);

        assertEq(ind.balanceOf(bob), 0);
        assertEq(ind.totalBalanceOf(bob), 20 ether);
    }

    function test_balanceOf_includes_unlocked_protected() external {
        vm.startPrank(alice);
        ind.protect(50 ether);
        ind.transferWithInheritance(bob, 20 ether, uint64(1 days), bytes32(0));
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);

        assertEq(ind.unprotectedBalanceOf(bob), 0);
        assertEq(ind.lockedBalanceOf(bob), 0);
        assertEq(ind.spendableBalanceOf(bob), 20 ether);
        assertEq(ind.protectedBalanceOf(bob), 20 ether);

        assertEq(ind.balanceOf(bob), 20 ether);
        assertEq(ind.totalBalanceOf(bob), 20 ether);
    }

    function test_balanceOf_includes_unprotected_plus_unlocked_protected() external {
        vm.startPrank(alice);
        ind.protect(50 ether);
        ind.transferWithInheritance(bob, 20 ether, uint64(1 days), bytes32(0));
        vm.stopPrank();

        vm.prank(sale);
        ind.mint(bob, 7 ether);

        assertEq(ind.balanceOf(bob), 7 ether);
        assertEq(ind.totalBalanceOf(bob), 27 ether);

        vm.warp(block.timestamp + 1 days + 1);

        assertEq(ind.balanceOf(bob), 27 ether);
        assertEq(ind.totalBalanceOf(bob), 27 ether);
    }
}
