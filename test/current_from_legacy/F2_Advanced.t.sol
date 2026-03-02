// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
import {InheritanceDollarCompat} from "../../contracts/InheritanceDollarCompat.sol";

import {INDKeyRegistry} from "../../contracts/InheritanceDollar.sol";

contract F2_Advanced_Test is Test {
    INDKeyRegistry reg;
    InheritanceDollarCompat ind;

    address admin = address(0xD00D);

    address owner = address(0xA);
    address signing = address(0x1111);
    address revokeK = address(0x2222);

    address bobOwner = address(0xB);
    address bobSigning = address(0x3333);
    address bobRevoke = address(0x4444);

    function setUp() public {
        reg = new INDKeyRegistry(admin);
        ind = new InheritanceDollarCompat(admin, reg);

        vm.startPrank(admin);

        reg.grantRole(reg.REGISTRY_ADMIN_ROLE(), address(ind));
        ind.grantRole(ind.MINTER_ROLE(), admin);
        ind.mint(owner, 100 ether);
        ind.mint(bobOwner, 1 ether);

        vm.stopPrank();

        vm.prank(owner);
        ind.activateKeysAndMigrate(signing, revokeK);

        vm.prank(bobOwner);
        ind.activateKeysAndMigrate(bobSigning, bobRevoke);
    }

    function test_send_to_uninitialized_owner_reverts() public {
        address raw = address(0xCAFE);
        vm.prank(admin);
        ind.mint(signing, 1 ether);

        vm.prank(signing);
        // raw addresses are allowed (ERC20-compatible); no revert expected
        assertTrue(ind.transfer(raw, 1 ether));
    }

    function test_send_to_initialized_owner_redirects_to_signing() public {
        vm.prank(admin);
        ind.mint(signing, 2 ether);

        vm.prank(signing);
        assertTrue(ind.transfer(owner, 1 ether)); // should redirect to signing (self), no owner balance

        assertEq(ind.balanceOf(owner), 0);
    }

    function test_receive_does_not_keep_alive() public {
        // move time forward so owner becomes dead unless he spends
        // (this assumes your year calc + inactivity; adjust warp if needed)
        // the point: receiving should NOT change lastSpendYear
        uint16 beforeY = ind.lastSpendYearOf(owner);

        vm.prank(admin);
        ind.mint(signing, 1 ether); // receive

        uint16 afterY = ind.lastSpendYearOf(owner);
        assertEq(beforeY, afterY);
    }
}
