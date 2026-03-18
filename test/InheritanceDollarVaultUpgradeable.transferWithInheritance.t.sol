// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../contracts/InheritanceDollarVaultUpgradeable.sol";
import "./mocks/MockINDKeyRegistryLite.sol";

contract InheritanceDollarVaultUpgradeableTransferWithInheritanceTest is Test {
    InheritanceDollarVaultUpgradeable internal ind;
    MockINDKeyRegistryLite internal reg;

    address internal admin = address(0xA11CE);
    address internal sale = address(0x5A1E);
    address internal alice = address(0xAAA1);
    address internal bob = address(0xBBB2);
    address internal carol = address(0xCCC3);

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

        vm.prank(sale);
        ind.mint(alice, 100 ether);
    }

    function test_transferWithInheritance_uses_only_protected_balance() external {
        vm.startPrank(alice);
        ind.protect(60 ether);
        assertTrue(ind.transferWithInheritance(bob, 40 ether, 86400, bytes32(0)));
        vm.stopPrank();

        assertEq(ind.balanceOf(alice), 40 ether);
        assertEq(ind.protectedBalanceOf(alice), 20 ether);

        assertEq(ind.balanceOf(bob), 0);
        assertEq(ind.protectedBalanceOf(bob), 40 ether);
    }

    function test_transferWithInheritance_reverts_if_only_unprotected_exists() external {
        vm.prank(alice);
        vm.expectRevert(InheritanceDollarVaultUpgradeable.InsufficientProtectedBalance.selector);
        ind.transferWithInheritance(bob, 10 ether, 86400, bytes32(0));

        assertEq(ind.balanceOf(alice), 100 ether);
        assertEq(ind.protectedBalanceOf(alice), 0);
        assertEq(ind.balanceOf(bob), 0);
        assertEq(ind.protectedBalanceOf(bob), 0);
    }

    function test_recipient_of_protected_transfer_cannot_bypass_with_erc20_transfer() external {
        vm.startPrank(alice);
        ind.protect(50 ether);
        ind.transferWithInheritance(bob, 50 ether, 86400, bytes32(0));
        vm.stopPrank();

        assertEq(ind.balanceOf(bob), 0);
        assertEq(ind.protectedBalanceOf(bob), 50 ether);

        vm.prank(bob);
        vm.expectRevert(InheritanceDollarVaultUpgradeable.InsufficientUnprotectedBalance.selector);
        ind.transfer(carol, 1 ether);

        assertEq(ind.balanceOf(carol), 0);
        assertEq(ind.protectedBalanceOf(carol), 0);
    }

    function test_transferWithInheritance_emits_protected_to_protected_only() external {
        vm.prank(alice);
        ind.protect(25 ether);

        vm.prank(alice);
        ind.transferWithInheritance(bob, 25 ether, uint64(1 days), bytes32(uint256(7)));

        assertEq(ind.balanceOf(alice), 75 ether);
        assertEq(ind.protectedBalanceOf(alice), 0);
        assertEq(ind.balanceOf(bob), 0);
        assertEq(ind.protectedBalanceOf(bob), 25 ether);
        assertEq(ind.totalUserBalanceOf(alice), 75 ether);
        assertEq(ind.totalUserBalanceOf(bob), 25 ether);
    }
}
