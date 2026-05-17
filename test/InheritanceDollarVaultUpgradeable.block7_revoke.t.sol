// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InheritanceDollarVaultUpgradeable} from "../contracts/InheritanceDollarVaultUpgradeable.sol";
import {MockINDKeyRegistryLite} from "./mocks/MockINDKeyRegistryLite.sol";

contract InheritanceDollarVaultUpgradeableBlock7RevokeTest is Test {
    InheritanceDollarVaultUpgradeable internal ind;
    MockINDKeyRegistryLite internal reg;

    address internal admin = address(0xA11CE);
    address internal sale = address(0x5A1E);
    address internal owner = address(0xAAA1);
    address internal signing = address(0x1111);
    address internal revokeK = address(0x2222);
    address internal bob = address(0xBBB2);
    address internal bobHot = address(0xB0B01);
    address internal bobCold = address(0xB0B02);
    address internal eve = address(0xEEE5);

    uint256 internal constant MAX_SUPPLY = 100_000_000_000 ether;

    function setUp() external {
        reg = new MockINDKeyRegistryLite();
        
        // Recipients of protected transfers must be explicitly protected-aware.
        reg.setOwnerKeys(bob, bobHot, bobCold);
        reg.unsafeSetProtectedAwareNoRedirect(eve);
InheritanceDollarVaultUpgradeable impl = new InheritanceDollarVaultUpgradeable();

        bytes memory initData =
            abi.encodeCall(InheritanceDollarVaultUpgradeable.initialize, (admin, MAX_SUPPLY, address(reg)));

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        ind = InheritanceDollarVaultUpgradeable(address(proxy));

        vm.startPrank(admin);
        ind.grantRole(ind.MINTER_ROLE(), sale);
        vm.stopPrank();

        vm.prank(sale);
        ind.mint(owner, 100 ether);

        reg.setOwnerKeys(owner, signing, revokeK);

        vm.prank(sale);
        ind.mint(signing, 50 ether);

        vm.prank(signing);
        ind.protect(50 ether);

        vm.prank(signing);
        ind.transferWithInheritance(bob, 20 ether, uint64(3 days), bytes32(0));
    }

    function test_revokeKey_can_revoke_locked_lot_and_refund_to_signingKey() external {
        uint256 beforeSigning = ind.balanceOf(signing);
        assertEq(ind.protectedBalanceOf(bobHot), 20 ether);

        vm.prank(revokeK);
        assertTrue(ind.revoke(bobHot, 0));

        assertEq(ind.protectedBalanceOf(bobHot), 0);
        assertEq(ind.balanceOf(signing), beforeSigning + 20 ether);
    }

    function test_owner_cannot_revoke_after_setup() external {
        vm.prank(owner);
        vm.expectRevert(InheritanceDollarVaultUpgradeable.NotRevoke.selector);
        ind.revoke(bobHot, 0);
    }

    function test_non_revoke_cannot_revoke() external {
        vm.prank(eve);
        vm.expectRevert(InheritanceDollarVaultUpgradeable.NotRevoke.selector);
        ind.revoke(bobHot, 0);
    }

    function test_cannot_revoke_unlocked_lot() external {
        vm.warp(block.timestamp + 3 days + 1);

        vm.prank(revokeK);
        vm.expectRevert(InheritanceDollarVaultUpgradeable.LotUnlocked.selector);
        ind.revoke(bobHot, 0);
    }

    function test_revoke_advances_head_when_revoking_first_lot() external {
        vm.prank(signing);
        ind.transferWithInheritance(bob, 5 ether, uint64(4 days), bytes32(0));

        assertEq(ind.headOf(bobHot), 0);

        vm.prank(revokeK);
        ind.revoke(bobHot, 0);

        assertEq(ind.headOf(bobHot), 1);
        assertEq(ind.protectedBalanceOf(bobHot), 5 ether);
    }
}
