// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InheritanceDollarVaultUpgradeable} from "../contracts/InheritanceDollarVaultUpgradeable.sol";
import {MockINDKeyRegistryLite} from "./mocks/MockINDKeyRegistryLite.sol";

contract InheritanceDollarVaultUpgradeableTest is Test {
    InheritanceDollarVaultUpgradeable internal ind;
    MockINDKeyRegistryLite internal reg;

    address internal admin = address(0xA11CE);
    address internal sale = address(0x5A1E);
    address internal alice = address(0xAAA1);
    address internal bob = address(0xBBB2);
    address internal carol = address(0xCCC3);

    uint256 internal constant MAX_SUPPLY = 100_000_000_000 ether; // 100B * 1e18

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
    }

    function test_init_keeps_name_symbol_decimals_and_max_supply() external view {
        assertEq(ind.name(), "Inheritance Dollar");
        assertEq(ind.symbol(), "IND");
        assertEq(ind.decimals(), 18);
        assertEq(ind.maxSupply(), MAX_SUPPLY);
    }

    function test_sale_mint_goes_to_unprotected_balance() external {
        vm.prank(sale);
        ind.mint(alice, 100 ether);

        assertEq(ind.balanceOf(alice), 100 ether);
        assertEq(ind.totalSupply(), 100 ether);
        assertEq(ind.protectedBalanceOf(alice), 0);
    }

    function test_transfer_uses_only_unprotected_balance() external {
        vm.prank(sale);
        ind.mint(alice, 100 ether);

        vm.prank(alice);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        assertTrue(ind.transfer(bob, 40 ether));

        assertEq(ind.unprotectedBalanceOf(alice), 60 ether);
        assertEq(ind.unprotectedBalanceOf(bob), 40 ether);
        assertEq(ind.protectedBalanceOf(alice), 0);
        assertEq(ind.protectedBalanceOf(bob), 0);
    }

    function test_protect_moves_unprotected_to_protected() external {
        vm.prank(sale);
        ind.mint(alice, 100 ether);

        vm.prank(alice);
        assertTrue(ind.protect(30 ether));

        assertEq(ind.unprotectedBalanceOf(alice), 70 ether);
        assertEq(ind.protectedBalanceOf(alice), 30 ether);
        assertEq(ind.balanceOf(alice), 100 ether);
    }

    function test_unprotect_moves_protected_to_unprotected() external {
        vm.prank(sale);
        ind.mint(alice, 100 ether);

        vm.startPrank(alice);
        ind.protect(30 ether);
        assertTrue(ind.unprotect(10 ether));
        vm.stopPrank();

        assertEq(ind.unprotectedBalanceOf(alice), 80 ether);
        assertEq(ind.protectedBalanceOf(alice), 20 ether);
        assertEq(ind.balanceOf(alice), 100 ether);
    }

    function test_transfer_cannot_spend_protected_balance() external {
        vm.prank(sale);
        ind.mint(alice, 100 ether);

        vm.prank(alice);
        ind.protect(60 ether);

        vm.prank(alice);
        vm.expectRevert(InheritanceDollarVaultUpgradeable.InsufficientUnprotectedBalance.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ind.transfer(bob, 50 ether);

        assertEq(ind.unprotectedBalanceOf(alice), 40 ether);
        assertEq(ind.protectedBalanceOf(alice), 60 ether);
    }

    function test_approve_and_transferFrom_use_only_unprotected() external {
        vm.prank(sale);
        ind.mint(alice, 100 ether);

        vm.prank(alice);
        ind.protect(70 ether);

        vm.prank(alice);
        assertTrue(ind.approve(bob, 50 ether));

        vm.prank(bob);
        vm.expectRevert(InheritanceDollarVaultUpgradeable.InsufficientUnprotectedBalance.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ind.transferFrom(alice, carol, 50 ether);

        vm.prank(bob);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        assertTrue(ind.transferFrom(alice, carol, 30 ether));

        assertEq(ind.unprotectedBalanceOf(alice), 0);
        assertEq(ind.unprotectedBalanceOf(carol), 30 ether);
        assertEq(ind.protectedBalanceOf(alice), 70 ether);
    }

    function test_only_minter_can_mint() external {
        vm.prank(alice);
        vm.expectRevert();
        ind.mint(alice, 1 ether);
    }

    function test_max_supply_is_enforced() external {
        vm.prank(sale);
        ind.mint(alice, MAX_SUPPLY);

        vm.prank(sale);
        vm.expectRevert(InheritanceDollarVaultUpgradeable.MaxSupplyExceeded.selector);
        ind.mint(bob, 1);
    }

    function test_total_supply_unchanged_by_protect_unprotect_and_transfer() external {
        vm.prank(sale);
        ind.mint(alice, 100 ether);

        uint256 ts0 = ind.totalSupply();

        vm.startPrank(alice);
        ind.protect(30 ether);
        ind.unprotect(10 ether);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        assertTrue(ind.transfer(bob, 20 ether));
        vm.stopPrank();

        assertEq(ind.totalSupply(), ts0);
        assertEq(ind.totalSupply(), 100 ether);
    }
}
