// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../contracts/InheritanceDollarVaultUpgradeable.sol";
import "./mocks/MockINDKeyRegistryLite.sol";

contract InheritanceDollarVaultUpgradeableBlock3SweepTest is Test {
    InheritanceDollarVaultUpgradeable internal ind;
    MockINDKeyRegistryLite internal reg;

    address internal admin = address(0xA11CE);
    address internal sale = address(0x5A1E);
    address internal alice = address(0xAAA1);
    address internal bob = address(0xBBB2);
    address internal dave = address(0xDDD4);
    address internal eve = address(0xEEE5);

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
        ind.mint(bob, 1 ether);
        vm.stopPrank();

        // inizializza la liveness di Bob
        vm.prank(bob);
        ind.transfer(admin, 1 ether);
    }

    function _prepareLotToBob() internal {
        vm.prank(alice);
        ind.protect(40 ether);

        vm.prank(alice);
        ind.transferWithInheritance(bob, 25 ether, uint64(1 days), bytes32(0));
    }

    function test_setDefaultHeir_sets_for_logical_owner() external {
        vm.prank(bob);
        assertTrue(ind.setDefaultHeir(dave));

        assertEq(ind.defaultHeirOf(bob), dave);
    }

    function test_sweepLot_reverts_if_recipient_alive() external {
        _prepareLotToBob();

        vm.prank(bob);
        ind.setDefaultHeir(dave);

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(eve);
        vm.expectRevert(InheritanceDollarVaultUpgradeable.RecipientDead.selector);
        ind.sweepLot(bob, 0);
    }

    function test_sweepLot_sends_to_defaultHeir_if_owner_dead_and_lot_unlocked() external {
        _prepareLotToBob();

        vm.prank(bob);
        ind.setDefaultHeir(dave);

        vm.warp(block.timestamp + 1 days + 1);
        uint64 deathTs = ind.deathTimestampOf(bob);
        vm.warp(deathTs + 1);

        vm.prank(eve);
        ind.sweepLot(bob, 0);

        assertEq(ind.balanceOf(dave), 25 ether);
        assertEq(ind.protectedBalanceOf(bob), 0);
        assertEq(ind.totalSupply(), 101 ether);
    }

    function test_sweepLot_burns_if_no_defaultHeir() external {
        _prepareLotToBob();

        uint256 tsBefore = ind.totalSupply();

        vm.warp(block.timestamp + 1 days + 1);
        uint64 deathTs = ind.deathTimestampOf(bob);
        vm.warp(deathTs + 1);

        vm.prank(eve);
        ind.sweepLot(bob, 0);

        assertEq(ind.protectedBalanceOf(bob), 0);
        assertEq(ind.totalSupply(), tsBefore - 25 ether);
    }

    function test_sweepLot_burns_if_defaultHeir_is_dead() external {
        _prepareLotToBob();

        // inizializza dave e poi fallo morire
        vm.startPrank(sale);
        ind.mint(dave, 1 ether);
        vm.stopPrank();

        vm.prank(dave);
        ind.transfer(admin, 1 ether);

        vm.prank(bob);
        ind.setDefaultHeir(dave);

        vm.warp(block.timestamp + 1 days + 1);
        uint64 deathTs = ind.deathTimestampOf(bob);
        vm.warp(deathTs + 1);

        uint256 tsBefore = ind.totalSupply();

        vm.prank(eve);
        ind.sweepLot(bob, 0);

        assertEq(ind.balanceOf(dave), 0);
        assertEq(ind.totalSupply(), tsBefore - 25 ether);
    }

    function test_sweepLot_reverts_if_lot_still_locked_even_if_owner_dead() external {
        vm.prank(alice);
        ind.protect(40 ether);

        vm.prank(alice);
        ind.transferWithInheritance(bob, 25 ether, uint64(8 * 365 days), bytes32(0));

        vm.prank(bob);
        ind.setDefaultHeir(dave);

        uint64 deathTs = ind.deathTimestampOf(bob);
        vm.warp(deathTs + 1);

        vm.prank(eve);
        vm.expectRevert(InheritanceDollarVaultUpgradeable.InsufficientProtectedBalance.selector);
        ind.sweepLot(bob, 0);
    }

    function test_sweepLot_advances_head_when_sweeping_first_lot() external {
        vm.prank(alice);
        ind.protect(60 ether);

        vm.prank(alice);
        ind.transferWithInheritance(bob, 10 ether, uint64(1 days), bytes32(0));

        vm.prank(alice);
        ind.transferWithInheritance(bob, 20 ether, uint64(1 days), bytes32(0));

        vm.prank(bob);
        ind.setDefaultHeir(dave);

        vm.warp(block.timestamp + 1 days + 1);
        uint64 deathTs = ind.deathTimestampOf(bob);
        vm.warp(deathTs + 1);

        assertEq(ind.headOf(bob), 0);

        vm.prank(eve);
        ind.sweepLot(bob, 0);

        assertEq(ind.headOf(bob), 1);
        assertEq(ind.balanceOf(dave), 10 ether);
        assertEq(ind.protectedBalanceOf(bob), 20 ether);
    }
}
