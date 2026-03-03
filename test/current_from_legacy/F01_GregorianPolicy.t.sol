// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./InheritanceDollar.t.sol";

contract F01_GregorianPolicy_Test is InheritanceDollarTest {
    function test_365_days_does_not_trigger_dead() public {
        address rOwner = address(0xB1);
        address rSK = address(0xB2);
        address rRK = address(0xB3);

        vm.prank(rOwner);
        ind.activateKeysAndMigrateWithHeir(rSK, rRK, address(0));

        vm.prank(admin);
        ind.mint(alice, 10 ether);

        vm.prank(alice);
        ind.transfer(rOwner, 5 ether);

        vm.warp(block.timestamp + 1 days);

        // simulate signed outgoing activity
        vm.prank(rSK);
        ind.transfer(address(0xD00D), 1);

        // warp exactly 365 days
        vm.warp(block.timestamp + 365 days);

        // should NOT be dead → sweep must revert
        vm.expectRevert();
        ind.sweepLot(rSK, 0);
    }

    function test_365_days_plus_one_allows_dead_transition() public {
        address rOwner = address(0xC1);
        address rSK = address(0xC2);
        address rRK = address(0xC3);

        vm.prank(rOwner);
        ind.activateKeysAndMigrateWithHeir(rSK, rRK, address(0));

        vm.prank(admin);
        ind.mint(alice, 10 ether);

        vm.prank(alice);
        ind.transfer(rOwner, 5 ether);

        vm.warp(block.timestamp + 1 days);

        vm.prank(rSK);
        ind.transfer(address(0xD00D), 1);

        // warp 365 days + 1 second
        vm.warp(block.timestamp + 365 days + 1);

        // now sweep SHOULD succeed (recipient dead)
        ind.sweepLot(rSK, 0);
    }
}
