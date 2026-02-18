// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/InheritanceDollar.sol";

contract InheritanceDollarTest is Test {
    INDKeyRegistry reg;
    InheritanceDollar ind;

    address admin = address(0xA11CE);
    address alice = address(0xA);
    address bob   = address(0xB);

    function setUp() public {
        reg = new INDKeyRegistry(admin);
        ind = new InheritanceDollar(admin, reg);

        // Nota importante: nel contratto attuale non esiste mint pubblico.
        // Per ora testiamo solo i revert "di regola" che non richiedono fondi spendibili.
    }

    function test_waitTooShort_reverts() public {
        vm.prank(alice);
        vm.expectRevert(bytes("wait-too-short"));
        ind.transferWithInheritance(bob, 1e18, uint64(86399), bytes32(0));
    }

    function test_mint_isImmediatelySpendable() public {
        vm.prank(admin);
        ind.mint(alice, 100 ether);

        assertEq(ind.balanceOf(alice), 100 ether);
        assertEq(ind.lockedBalanceOf(alice), 0);
        assertEq(ind.spendableBalanceOf(alice), 100 ether);
    }


    function test_mint_transfer_lock_and_unlock() public {
        // Admin mints 100 to Alice
        vm.prank(admin);
        ind.mint(alice, 100 ether);

        // Alice transfers 10 to Bob (default wait = 86400)
        vm.prank(alice);
        ind.transfer(bob, 10 ether);

        // Immediately after transfer
        assertEq(ind.balanceOf(bob), 10 ether);
        assertEq(ind.lockedBalanceOf(bob), 10 ether);
        assertEq(ind.spendableBalanceOf(bob), 0);

        // Warp 24 hours
        vm.warp(block.timestamp + 86400);

        assertEq(ind.lockedBalanceOf(bob), 0);
        assertEq(ind.spendableBalanceOf(bob), 10 ether);
    }

    function test_invariant_balance_equals_locked_plus_spendable() public {
        vm.prank(admin);
        ind.mint(alice, 50 ether);

        vm.prank(alice);
        ind.transfer(bob, 20 ether);

        uint256 balance = ind.balanceOf(bob);
        uint256 locked = ind.lockedBalanceOf(bob);
        uint256 spendable = ind.spendableBalanceOf(bob);

        assertEq(balance, locked + spendable);
    }


    function test_reduceUnlockTime_valid_and_invalid() public {
        vm.prank(admin);
        ind.mint(alice, 100 ether);

        vm.prank(alice);
        ind.transferWithInheritance(bob, 10 ether, 90000, bytes32(0));

        // Try increasing unlockTime → must revert
        vm.prank(alice);
        vm.expectRevert(bytes("not-reduction"));
        ind.reduceUnlockTime(bob, 0, uint64(block.timestamp + 95000));

        // Try below minimum → revert
        vm.prank(alice);
        vm.expectRevert(bytes("below-min"));
        ind.reduceUnlockTime(bob, 0, uint64(block.timestamp + 100));

        // Valid reduction
        vm.prank(alice);
        ind.reduceUnlockTime(bob, 0, uint64(block.timestamp + 86400));
    }

    function test_revoke_before_and_after_unlock() public {
        vm.prank(admin);
        ind.mint(alice, 100 ether);

        vm.prank(alice);
        ind.transfer(bob, 10 ether);

        // Revoke before unlock
        vm.prank(alice);
        ind.revoke(bob, 0);

        assertEq(ind.balanceOf(bob), 0);

        // Mint again and transfer
        vm.prank(admin);
        ind.mint(alice, 10 ether);

        vm.prank(alice);
        ind.transfer(bob, 10 ether);

        vm.warp(block.timestamp + 86400);

        vm.prank(alice);
        vm.expectRevert(bytes("already-unlocked"));
        ind.revoke(bob, 1);
    }

    function test_transferFrom_cannot_bypass_lock() public {
        vm.prank(admin);
        ind.mint(alice, 100 ether);

        vm.prank(alice);
        ind.transfer(bob, 20 ether);

        vm.prank(bob);
        ind.approve(alice, 20 ether);

        vm.prank(alice);
        vm.expectRevert(bytes("insufficient-spendable"));
        ind.transferFrom(bob, alice, 1 ether);
    }

    function test_separate_keys_should_control_revoke_but_currently_fail() public {
        vm.prank(admin);
        ind.mint(alice, 100 ether);

        vm.prank(alice);
        ind.transfer(bob, 10 ether);

        // Simulate a different address trying revoke
        address revokeKey = address(0xDEAD);

        vm.prank(revokeKey);
        vm.expectRevert(); // Should revert today (not senderOwner)
        ind.revoke(bob, 1);
    }

}
