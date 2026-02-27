// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "contracts/InheritanceDollarCompat.sol";

contract F3_PropertySweep_Test is Test {
    INDKeyRegistry reg;
    InheritanceDollarCompat ind;

    address admin = address(0xA11CE);
    address alice = address(0xA);
    address bob = address(0xB);

    function setUp() public {
        reg = new INDKeyRegistry(admin);
        ind = new InheritanceDollarCompat(admin, reg);

        vm.startPrank(admin);
        reg.grantRole(reg.REGISTRY_ADMIN_ROLE(), address(ind));
        vm.stopPrank();
    }

    function test_property_no_unintended_burn() public {
        vm.startPrank(admin);
        ind.mint(alice, 10 ether);
        vm.stopPrank();

        vm.prank(alice);
        ind.transfer(bob, 10 ether);

        vm.warp(block.timestamp + ind.MIN_WAIT_SECONDS());

        uint256 supplyBefore = ind.totalSupply();

        // attempt sweep
        try ind.sweepLot(bob, 0) {} catch {}

        uint256 supplyAfter = ind.totalSupply();

        // If supply decreased, then both must be dead.
        if (supplyAfter < supplyBefore) {
            // If burn happened, recipient must be dead
            // and sender must be dead
            // Otherwise this is a violation
            bool recipientDead = false;
            bool senderDead = false;

            // We simulate detection logic:
            // Since no activation happened,
            // accounts are treated alive.

            assertTrue(recipientDead && senderDead);
        }
    }

    function test_property_burn_implies_recipient_dead() public {
        vm.startPrank(admin);
        ind.mint(alice, 10 ether);
        vm.stopPrank();

        vm.prank(alice);
        ind.transfer(bob, 10 ether);

        vm.warp(block.timestamp + ind.MIN_WAIT_SECONDS());

        uint256 supplyBefore = ind.totalSupply();

        // Attempt sweep (recipient still alive)
        try ind.sweepLot(bob, 0) {} catch {}

        uint256 supplyAfter = ind.totalSupply();

        // If supply decreased here, it's a bug
        assertEq(supplyAfter, supplyBefore);
    }

    function test_property_burn_happens_only_when_fully_dead() public {
        address sOwner = address(0xAA01);
        address sSK = address(0xAA02);
        address sRK = address(0xAA03);

        address rOwner = address(0xBB01);
        address rSK = address(0xBB02);
        address rRK = address(0xBB03);

        // initialize keys
        vm.prank(sOwner);
        ind.activateKeysAndMigrateWithHeir(sSK, sRK, address(0));

        vm.prank(rOwner);
        ind.activateKeysAndMigrateWithHeir(rSK, rRK, address(0));

        // fund sender
        vm.prank(admin);
        ind.mint(sSK, 20 ether);

        vm.prank(admin);
        ind.mint(rSK, 2 ether);

        // touch outgoing so inactivity timer starts
        vm.prank(sSK);
        ind.transfer(address(0xD00D), 1);

        vm.prank(rSK);
        ind.transfer(address(0xD00D), 1);

        // create inheritance lot

        vm.startPrank(sSK);
        ind.transferWithInheritance(rSK, 10 ether, ind.MIN_WAIT_SECONDS(), bytes32("X"));
        vm.stopPrank();

        // unlock + advance beyond DEAD_AFTER_SECONDS
        vm.warp(block.timestamp + ind.MIN_WAIT_SECONDS());
        vm.warp(block.timestamp + uint256(ind.DEAD_AFTER_SECONDS()) + 1);

        uint256 supplyBefore = ind.totalSupply();

        ind.sweepLot(rSK, ind.getLots(rSK).length - 1);

        uint256 supplyAfter = ind.totalSupply();

        // since both dead and no heir, must burn
        assertEq(supplyBefore - supplyAfter, 10 ether);
    }
}
