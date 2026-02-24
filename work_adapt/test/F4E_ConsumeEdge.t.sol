// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./InheritanceDollar.t.sol";

contract F4E_ConsumeEdge is InheritanceDollarTest {

    // sweepLot requires recipient DEAD.
    // To make recipient dead we must:
    // 1) have an initialized owner (rOwner) with a signingKey (rSK)
    // 2) make rSK do at least one outgoing transfer (this sets _lastSignedOutTs[rOwner])
    // 3) warp beyond DEAD_AFTER_SECONDS
    function test_doubleSweep_revertsEmpty() public {
        // recipient owner + keys
        address rOwner = address(0xBB01);
        address rSK    = address(0xBB02);
        address rRK    = address(0xBB03);

        // activate recipient keys (default heir = 0)
        vm.prank(rOwner);
        ind.activateKeysAndMigrateWithHeir(rSK, rRK, address(0));

        // fund alice and create lot to rOwner (will be redirected to rSK)
        vm.prank(admin);
        ind.mint(alice, 20 ether);

        vm.prank(alice);
        ind.transfer(rOwner, 10 ether);

        // unlock lots
        vm.warp(block.timestamp + 1 days);

        // touch signed outgoing for recipient owner (must be from signingKey!)
        vm.prank(rSK);
        ind.transfer(address(0xD00D), 1); // spends 1 wei from unlocked lot, sets lastSignedOutTs[rOwner]

        // now warp beyond dead threshold
        vm.warp(block.timestamp + uint256(ind.DEAD_AFTER_SECONDS()) + 1);

        // first sweep should succeed (refund path, since sender alice is "alive" by definition)
        ind.sweepLot(rSK, 0);

        // second sweep must revert empty-lot
        vm.expectRevert(bytes("empty-lot"));
        ind.sweepLot(rSK, 0);
    }

    function test_lockedCannotBeConsumedEarly() public {
        vm.prank(admin);
        ind.mint(alice, 10 ether);

        vm.prank(alice);
        ind.transferWithInheritance(bob, 5 ether, 2 days, bytes32(0));

        vm.prank(bob);
        vm.expectRevert(bytes("insufficient-spendable"));
        ind.transfer(alice, 1 ether);
    }

    function test_headDoesNotSkipPartialLot() public {
        vm.prank(admin);
        ind.mint(alice, 20 ether);

        vm.prank(alice);
        ind.transfer(bob, 10 ether);

        vm.warp(block.timestamp + 1 days);

        vm.prank(bob);
        ind.transfer(alice, 5 ether);

        // remaining must still be 5 ether spendable
        assertEq(ind.spendableBalanceOf(bob), 5 ether);
    }

    function test_mixedLockedUnlockedConsumption() public {
        vm.prank(admin);
        ind.mint(alice, 30 ether);

        // lot 0 unlocks in 1 day
        vm.prank(alice);
        ind.transferWithInheritance(bob, 10 ether, 1 days, bytes32(0));

        // lot 1 unlocks in 3 days
        vm.prank(alice);
        ind.transferWithInheritance(bob, 10 ether, 3 days, bytes32(0));

        vm.warp(block.timestamp + 2 days);

        // only first lot unlocked (10 ether)
        vm.prank(bob);
        ind.transfer(alice, 7 ether);

        assertEq(ind.spendableBalanceOf(bob), 3 ether);
        assertEq(ind.lockedBalanceOf(bob), 10 ether);
    }
}
