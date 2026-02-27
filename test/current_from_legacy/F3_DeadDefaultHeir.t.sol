// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./InheritanceDollar.t.sol";

contract F3_DeadDefaultHeir_Test is InheritanceDollarTest {
    function test_F3_bothDead_goesToDefaultHeir() public {
        // owners + keys
        address sOwner = address(0xA11CE);
        address sSK = address(0xA11C3);
        address sRK = address(0xA11C4);

        address rOwner = address(0xB0B01);
        address rSK = address(0xB0B02);
        address rRK = address(0xB0B03);

        address heir = address(0xC0FFEE);

        // initialize keys + set default heir for recipient owner
        vm.prank(sOwner);
        ind.activateKeysAndMigrateWithHeir(sSK, sRK, address(0));

        vm.prank(rOwner);
        ind.activateKeysAndMigrateWithHeir(rSK, rRK, heir);

        // fund signing keys
        vm.startPrank(admin);
        ind.mint(sSK, 100 ether);
        ind.mint(rSK, 2 ether);
        vm.stopPrank();
        // make BOTH owners "not-last=0" then dead later:
        // any outgoing transfer from signingKey touches _lastSignedOutTs[owner]
        vm.prank(sSK);
        ind.transfer(address(0xD00D), 1);
        vm.prank(rSK);
        ind.transfer(address(0xD00D), 1);
        // create the inheritance lot from sender signingKey to recipient signingKey
        vm.prank(sSK);
        ind.transferWithInheritance(rSK, 10 ether, uint64(86400), bytes32("X"));

        // get lot index (last one)
        InheritanceDollar.Lot[] memory lots = ind.getLots(rSK);
        uint256 lotIndex = lots.length - 1;

        // warp beyond DEAD_AFTER_SECONDS (also beyond unlock)
        vm.warp(block.timestamp + uint256(ind.DEAD_AFTER_SECONDS()) + 1);

        uint256 heirBefore = ind.balanceOf(heir);

        // permissionless sweep
        ind.sweepLot(rSK, lotIndex);

        assertEq(ind.balanceOf(heir), heirBefore + 10 ether);
    }

    function test_F3_bothDead_noHeir_burns() public {
        address sOwner = address(0xAA01);
        address sSK = address(0xAA02);
        address sRK = address(0xAA03);

        address rOwner = address(0xBB01);
        address rSK = address(0xBB02);
        address rRK = address(0xBB03);

        // init keys, NO default heir set for recipient
        vm.prank(sOwner);
        ind.activateKeysAndMigrateWithHeir(sSK, sRK, address(0));

        vm.prank(rOwner);
        ind.activateKeysAndMigrateWithHeir(rSK, rRK, address(0));

        vm.startPrank(admin);
        ind.mint(sSK, 100 ether);
        ind.mint(rSK, 2 ether);
        vm.stopPrank();
        // touch outgoing for both to enable dead detection later
        vm.prank(sSK);
        ind.transfer(address(0xD00D), 1);
        vm.prank(rSK);
        ind.transfer(address(0xD00D), 1);
        // create lot
        vm.prank(sSK);
        ind.transferWithInheritance(rSK, 7 ether, uint64(86400), bytes32("Y"));

        InheritanceDollar.Lot[] memory lots = ind.getLots(rSK);
        uint256 lotIndex = lots.length - 1;

        uint256 supplyBefore = ind.totalSupply();
        uint256 rBefore = ind.balanceOf(rSK);

        vm.warp(block.timestamp + uint256(ind.DEAD_AFTER_SECONDS()) + 1);

        ind.sweepLot(rSK, lotIndex);

        // burned from recipient balance
        assertEq(ind.totalSupply(), supplyBefore - 7 ether);
        assertEq(ind.balanceOf(rSK), rBefore - 7 ether);
    }
}
