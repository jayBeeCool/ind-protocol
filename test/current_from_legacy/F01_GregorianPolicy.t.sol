// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {InheritanceDollarTest} from "./InheritanceDollar.t.sol";

contract F01_GregorianPolicy_Test is InheritanceDollarTest {
    function test_365_days_does_not_trigger_dead() public {
        address rOwner = address(0xB1);
        address rSk = address(0xB2);
        address rRk = address(0xB3);

        vm.prank(rOwner);
        ind.activateKeysAndMigrateWithHeir(rSk, rRk, address(0));

        vm.prank(admin);
        ind.mint(alice, 10 ether);

        vm.prank(alice);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        assertTrue(ind.transfer(rOwner, 5 ether));

        vm.warp(block.timestamp + 1 days);

        vm.prank(rSk);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        assertTrue(ind.transfer(address(0xD00D), 1));

        vm.warp(block.timestamp + 365 days);

        vm.expectRevert();
        ind.sweepLot(rSk, 0);
    }

    function test_365_days_plus_one_allows_dead_transition() public {
        address rOwner = address(0xC1);
        address rSk = address(0xC2);
        address rRk = address(0xC3);

        vm.prank(rOwner);
        ind.activateKeysAndMigrateWithHeir(rSk, rRk, address(0));

        vm.prank(admin);
        ind.mint(alice, 10 ether);

        vm.prank(alice);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        assertTrue(ind.transfer(rOwner, 5 ether));

        vm.warp(block.timestamp + 1 days);

        vm.prank(rSk);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        assertTrue(ind.transfer(address(0xD00D), 1));

        vm.warp(block.timestamp + 365 days + 1);

        ind.sweepLot(rSk, 0);
    }
}
