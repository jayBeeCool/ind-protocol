// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./InheritanceDollar.t.sol";

contract F3_DeadDefaultHeir_Test is InheritanceDollarTest {
    function test_F3_bothDead_goesToDefaultHeir() public {
        // owners + keys
        address sOwner = address(0xA11CE);
        address sSk = address(0xA11C3);
        address sRk = address(0xA11C4);

        address rOwner = address(0xB0B01);
        address rSk = address(0xB0B02);
        address rRk = address(0xB0B03);

        address heir = address(0xC0FFEE);

        // initialize keys + set default heir for recipient owner
        vm.prank(sOwner);
        ind.activateKeysAndMigrateWithHeir(sSk, sRk, address(0));

        vm.prank(rOwner);
        ind.activateKeysAndMigrateWithHeir(rSk, rRk, heir);

        // fund signing keys
        vm.startPrank(admin);
        ind.mint(sSk, 100 ether);
        ind.mint(rSk, 2 ether);
        vm.stopPrank();
        // make BOTH owners "not-last=0" then dead later:
        // any outgoing transfer from signingKey touches _lastSignedOutTs[owner]
        vm.prank(sSk);
        require(ind.transfer(address(0xD00D), 1));
        vm.prank(rSk);
        require(ind.transfer(address(0xD00D), 1));
        // create the inheritance lot from sender signingKey to recipient signingKey
        vm.prank(sSk);
        ind.transferWithInheritance(rSk, 10 ether, uint64(86400), keccak256("X"));

        // get lot index (last one)
        InheritanceDollar.Lot[] memory lots = ind.getLots(rSk);
        uint256 lotIndex = lots.length - 1;

        // warp beyond DEAD_AFTER_SECONDS (also beyond unlock)
        vm.warp(block.timestamp + uint256(ind.DEAD_AFTER_SECONDS()) + 1);

        uint256 heirBefore = ind.balanceOf(heir);

        // permissionless sweep
        ind.sweepLot(rSk, lotIndex);

        assertEq(ind.balanceOf(heir), heirBefore + 10 ether);
    }

    function test_F3_bothDead_noHeir_burns() public {
        address sOwner = address(0xAA01);
        address sSk = address(0xAA02);
        address sRk = address(0xAA03);

        address rOwner = address(0xBB01);
        address rSk = address(0xBB02);
        address rRk = address(0xBB03);

        // init keys, NO default heir set for recipient
        vm.prank(sOwner);
        ind.activateKeysAndMigrateWithHeir(sSk, sRk, address(0));

        vm.prank(rOwner);
        ind.activateKeysAndMigrateWithHeir(rSk, rRk, address(0));

        vm.startPrank(admin);
        ind.mint(sSk, 100 ether);
        ind.mint(rSk, 2 ether);
        vm.stopPrank();
        // touch outgoing for both to enable dead detection later
        vm.prank(sSk);
        require(ind.transfer(address(0xD00D), 1));
        vm.prank(rSk);
        require(ind.transfer(address(0xD00D), 1));
        // create lot
        vm.prank(sSk);
        ind.transferWithInheritance(rSk, 7 ether, uint64(86400), keccak256("Y"));

        InheritanceDollar.Lot[] memory lots = ind.getLots(rSk);
        uint256 lotIndex = lots.length - 1;

        uint256 supplyBefore = ind.totalSupply();
        uint256 rBefore = ind.balanceOf(rSk);

        vm.warp(block.timestamp + uint256(ind.DEAD_AFTER_SECONDS()) + 1);

        ind.sweepLot(rSk, lotIndex);

        // burned from recipient balance
        assertEq(ind.totalSupply(), supplyBefore - 7 ether);
        assertEq(ind.balanceOf(rSk), rBefore - 7 ether);
    }
}
