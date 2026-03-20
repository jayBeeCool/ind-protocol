// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../contracts/InheritanceDollarVaultUpgradeable.sol";
import "./mocks/MockINDKeyRegistryLite.sol";

contract InheritanceDollarVaultUpgradeableRulesTest is Test {
    InheritanceDollarVaultUpgradeable internal ind;
    MockINDKeyRegistryLite internal reg;

    address internal admin = address(0xA11CE);
    address internal sale = address(0x5A1E);
    address internal alice = address(0xAAA1);
    address internal bob = address(0xBBB2);

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

        vm.prank(alice);
        ind.protect(100 ether);
    }

    function test_constants_are_correct() external view {
        assertEq(ind.MIN_INHERITANCE_WAIT(), 1 days);
        assertEq(ind.INACTIVITY_YEARS(), 7);
        assertEq(ind.MAX_WAIT_YEARS(), 50);
    }

    function test_transferWithInheritance_reverts_below_24h() external {
        vm.prank(alice);
        vm.expectRevert(InheritanceDollarVaultUpgradeable.InheritanceWaitTooShort.selector);
        ind.transferWithInheritance(bob, 1 ether, uint64(1 days - 1), bytes32(0));
    }

    function test_transferWithInheritance_accepts_exactly_max_gregorian_wait() external {
        uint64 maxWait = ind.maxInheritanceWaitNow();

        vm.prank(alice);
        assertTrue(ind.transferWithInheritance(bob, 1 ether, maxWait, bytes32(0)));

        assertEq(ind.protectedBalanceOf(bob), 1 ether);
        assertEq(ind.balanceOf(bob), 1 ether);
    }

    function test_transferWithInheritance_reverts_above_max_gregorian_wait() external {
        uint64 maxWait = ind.maxInheritanceWaitNow();

        vm.prank(alice);
        vm.expectRevert(InheritanceDollarVaultUpgradeable.InheritanceWaitTooLong.selector);
        ind.transferWithInheritance(bob, 1 ether, maxWait + 1, bytes32(0));
    }

    function test_isDead_after_7_gregorian_years_without_interaction() external {
        uint64 deathTs = ind.deathTimestampOf(alice);
        assertGt(deathTs, 0);

        vm.warp(deathTs);
        assertFalse(ind.isDead(alice));

        vm.warp(deathTs + 1);
        assertTrue(ind.isDead(alice));
    }

    function test_passive_receipt_does_not_refresh_lastInteraction() external {
        uint64 bobBefore = ind.lastInteractionOf(bob);
        assertEq(bobBefore, 0);

        vm.prank(alice);
        ind.transferWithInheritance(bob, 5 ether, uint64(1 days), bytes32(uint256(123)));

        uint64 bobAfter = ind.lastInteractionOf(bob);
        assertEq(bobAfter, 0);

        assertEq(ind.protectedBalanceOf(bob), 5 ether);
        assertEq(ind.balanceOf(bob), 5 ether);
    }

    function test_sender_interaction_refreshes_lastInteraction() external {
        uint64 beforeTs = ind.lastInteractionOf(alice);

        vm.warp(block.timestamp + 10);
        vm.prank(alice);
        ind.transferWithInheritance(bob, 1 ether, uint64(1 days), bytes32(0));

        uint64 afterTs = ind.lastInteractionOf(alice);
        assertGt(afterTs, beforeTs);
    }

    function test_keepAlive_refreshes_renew_branch_only_but_prevents_death_if_signedout_is_old() external {
        uint64 deathTs = ind.deathTimestampOf(alice);
        assertGt(deathTs, 0);

        vm.warp(deathTs);
        vm.prank(alice);
        ind.keepAlive();

        vm.warp(block.timestamp + 1);
        assertFalse(ind.isDead(alice));
    }
}
