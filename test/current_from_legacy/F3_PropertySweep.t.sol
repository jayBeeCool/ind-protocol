// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
import "../../contracts/InheritanceDollarCompat.sol";

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

        uint64 w = ind.MIN_WAIT_SECONDS();

        vm.prank(alice);
        ind.transferWithInheritance(bob, 10 ether, w, bytes32(0));

        vm.warp(block.timestamp + w);

        uint256 supplyBefore = ind.totalSupply();

        try ind.sweepLot(bob, 0) {} catch {}

        uint256 supplyAfter = ind.totalSupply();

        // sender alice è vivo, quindi anche se sweep parte non deve bruciare:
        // al massimo rimborsa/refonde, ma la supply non deve scendere.
        assertEq(supplyAfter, supplyBefore);
    }

    function test_property_burn_implies_recipient_dead() public {
        address rOwner = address(0xB101);
        address rSk = address(0xB102);
        address rRk = address(0xB103);

        vm.prank(rOwner);
        ind.activateKeysAndMigrateWithHeir(rSk, rRk, address(0));

        vm.startPrank(admin);
        ind.mint(alice, 10 ether);
        ind.mint(rSk, 2 ether);
        vm.stopPrank();

        uint64 w = ind.MIN_WAIT_SECONDS();

        vm.prank(alice);
        ind.transferWithInheritance(rSk, 10 ether, w, bytes32(0));

        vm.warp(block.timestamp + w);

        // destinatario ancora vivo: facciamo un outgoing firmato recente
        vm.prank(rSk);
        ind.transfer(address(0xD00D), 1);

        uint256 lotIndex = ind.getLots(rSk).length - 1;
        vm.expectRevert(bytes("recipient-alive"));
        ind.sweepLot(rSk, lotIndex);
    }

    function test_property_burn_happens_only_when_fully_dead() public {
        address sOwner = address(0xAA01);
        address sSk = address(0xAA02);
        address sRk = address(0xAA03);

        address rOwner = address(0xBB01);
        address rSk = address(0xBB02);
        address rRk = address(0xBB03);

        // initialize keys
        vm.prank(sOwner);
        ind.activateKeysAndMigrateWithHeir(sSk, sRk, address(0));

        vm.prank(rOwner);
        ind.activateKeysAndMigrateWithHeir(rSk, rRk, address(0));

        // fund sender
        vm.prank(admin);
        ind.mint(sSk, 20 ether);

        vm.prank(admin);
        ind.mint(rSk, 2 ether);

        // touch outgoing so inactivity timer starts
        vm.prank(sSk);
        require(ind.transfer(address(0xD00D), 1));
        vm.prank(rSk);
        require(ind.transfer(address(0xD00D), 1));
        // create inheritance lot

        vm.startPrank(sSk);
        ind.transferWithInheritance(rSk, 10 ether, ind.MIN_WAIT_SECONDS(), keccak256("X"));
        vm.stopPrank();

        // unlock + advance beyond DEAD_AFTER_SECONDS
        vm.warp(block.timestamp + ind.MIN_WAIT_SECONDS());
        vm.warp(block.timestamp + uint256(ind.DEAD_AFTER_SECONDS()) + 1);

        uint256 supplyBefore = ind.totalSupply();

        ind.sweepLot(rSk, ind.getLots(rSk).length - 1);

        uint256 supplyAfter = ind.totalSupply();

        // since both dead and no heir, must burn
        assertEq(supplyBefore - supplyAfter, 10 ether);
    }
}
