// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InheritanceDollarVaultUpgradeable} from "../contracts/InheritanceDollarVaultUpgradeable.sol";
import {MockINDKeyRegistryLite} from "./mocks/MockINDKeyRegistryLite.sol";

contract InheritanceDollarVaultUpgradeableRevocationSeamTest is Test {
    InheritanceDollarVaultUpgradeable internal ind;
    MockINDKeyRegistryLite internal reg;

    address internal admin = address(0xA11CE);
    address internal sale = address(0x5A1E);

    address internal alice = address(0xAAA1);
    address internal aliceHot = address(0xA1101);
    address internal aliceCold = address(0xA1102);

    address internal bob = address(0xBBB2);
    address internal bobHot = address(0xB0B01);
    address internal bobCold = address(0xB0B02);

    address internal revokeOperator = aliceCold;

    function setUp() external {
        reg = new MockINDKeyRegistryLite();

        InheritanceDollarVaultUpgradeable impl = new InheritanceDollarVaultUpgradeable();

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(
                InheritanceDollarVaultUpgradeable.initialize,
                (admin, 1_000_000_000_000 ether, address(reg))
            )
        );

        ind = InheritanceDollarVaultUpgradeable(address(proxy));

        vm.startPrank(admin);
        ind.grantRole(ind.MINTER_ROLE(), sale);
        vm.stopPrank();

        reg.setOwnerKeys(alice, aliceHot, aliceCold);
        reg.setOwnerKeys(bob, bobHot, bobCold);

        vm.prank(sale);
        ind.mint(aliceHot, 100 ether);

        vm.prank(aliceHot);
        ind.protect(50 ether);
    }

    function _createProtectedLot() internal {
        vm.prank(aliceHot);
        ind.transferWithInheritance(
            bob,
            10 ether,
            uint64(2 days),
            keccak256("REV-SEAM")
        );
    }

    function test_revoke_before_unlock_succeeds() external {
        _createProtectedLot();

        vm.warp(block.timestamp + 12 hours);

        vm.prank(revokeOperator);
        ind.reduceUnlockTime(
            bobHot,
            0,
            uint64(block.timestamp + 1 days)
        );
    }

    function test_revoke_after_unlock_fails() external {
        _createProtectedLot();

        vm.warp(block.timestamp + 2 days + 1);

        vm.prank(revokeOperator);
        vm.expectRevert();
        ind.reduceUnlockTime(
            bobHot,
            0,
            uint64(block.timestamp + 1 days)
        );
    }

    function test_protected_not_convertible_before_unlock() external {
        _createProtectedLot();

        vm.prank(bobHot);
        vm.expectRevert();
        ind.unprotect(1 ether);
    }

    function test_protected_convertible_after_unlock() external {
        _createProtectedLot();

        vm.warp(block.timestamp + 2 days + 1);

        vm.prank(bobHot);
        ind.unprotect(10 ether);
    }

    function test_after_conversion_old_lot_cannot_be_revoked() external {
        _createProtectedLot();

        vm.warp(block.timestamp + 2 days + 1);

        vm.prank(bobHot);
        ind.unprotect(10 ether);

        vm.prank(revokeOperator);
        vm.expectRevert();
        ind.reduceUnlockTime(
            bobHot,
            0,
            uint64(block.timestamp + 1 days)
        );
    }

    function test_no_simultaneous_revocable_protected_and_spendable_unprotected() external {
        _createProtectedLot();

        vm.warp(block.timestamp + 12 hours);

        vm.prank(bobHot);
        vm.expectRevert();
        ind.transfer(aliceHot, 1 ether);

        vm.prank(revokeOperator);
        ind.reduceUnlockTime(
            bobHot,
            0,
            uint64(block.timestamp + 1 days)
        );

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(bobHot);
        ind.unprotect(10 ether);

        vm.prank(bobHot);
        assertTrue(ind.transfer(alice, 1 ether));
    }

    function test_transferFrom_only_after_post_unlock_conversion() external {
        _createProtectedLot();

        vm.prank(bobHot);
        ind.approve(aliceHot, type(uint256).max);

        vm.prank(aliceHot);
        vm.expectRevert();
        ind.transferFrom(bobHot, aliceHot, 1 ether);

        vm.warp(block.timestamp + 2 days + 1);

        vm.prank(bobHot);
        ind.unprotect(10 ether);

        vm.prank(aliceHot);
        assertTrue(ind.transferFrom(bobHot, aliceHot, 1 ether));
    }
}
