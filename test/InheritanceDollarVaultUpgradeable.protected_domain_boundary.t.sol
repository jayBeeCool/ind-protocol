// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InheritanceDollarVaultUpgradeable} from "../contracts/InheritanceDollarVaultUpgradeable.sol";
import {MockINDKeyRegistryLite} from "./mocks/MockINDKeyRegistryLite.sol";

contract GenericContractRecipient {}

contract InheritanceDollarVaultUpgradeableProtectedDomainBoundaryTest is Test {
    InheritanceDollarVaultUpgradeable internal ind;
    MockINDKeyRegistryLite internal reg;

    address internal admin = address(0xA11CE);
    address internal sale = address(0x5A1E);
    address internal alice = address(0xAAA1);
    address internal bob = address(0xBBB2);
    address internal bobHot = address(0xB0B01);
    address internal bobCold = address(0xB0B02);
    address internal carol = address(0xCCC3);
    address internal spender = address(0x5150);
    address internal genericContract;

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

        vm.prank(sale);
        ind.mint(alice, 100 ether);

        genericContract = address(new GenericContractRecipient());

        // Bob is a real protected-aware owner; protected receipts resolve to bobHot.
        reg.setOwnerKeys(bob, bobHot, bobCold);

        // Carol only needs to be an allowed protected recipient in these tests.
        reg.unsafeSetProtectedAwareNoRedirect(carol);
    }

    function _createLockedProtectedLot(address to, uint256 amount) internal {
        vm.prank(alice);
        ind.protect(amount);

        vm.prank(alice);
        ind.transferWithInheritance(to, amount, uint64(1 days), keccak256("LOCKED"));
    }

    function test_locked_protected_not_spendable_via_transfer() external {
        _createLockedProtectedLot(bob, 10 ether);

        vm.prank(bobHot);
        vm.expectRevert();
        ind.transfer(carol, 1 ether);
    }

    function test_locked_protected_not_spendable_via_transferFrom() external {
        _createLockedProtectedLot(bob, 10 ether);

        vm.prank(bobHot);
        ind.approve(spender, 10 ether);

        vm.prank(spender);
        vm.expectRevert();
        ind.transferFrom(bob, carol, 1 ether);
    }

    function test_protected_not_sendable_to_unregistered_eoa() external {
        vm.prank(alice);
        ind.protect(10 ether);

        address raw = address(0xDEAD);

        vm.prank(alice);
        vm.expectRevert(InheritanceDollarVaultUpgradeable.RecipientNotProtectedAware.selector);
        ind.transferWithInheritance(raw, 1 ether, uint64(1 days), keccak256("RAW"));
    }

    function test_protected_not_sendable_to_generic_contract() external {
        vm.prank(alice);
        ind.protect(10 ether);

        vm.prank(alice);
        vm.expectRevert(InheritanceDollarVaultUpgradeable.RecipientNotProtectedAware.selector);
        ind.transferWithInheritance(genericContract, 1 ether, uint64(1 days), keccak256("CONTRACT"));
    }

    function test_locked_protected_not_convertible_before_unlock() external {
        _createLockedProtectedLot(bob, 10 ether);

        vm.prank(bobHot);
        vm.expectRevert();
        ind.unprotect(1 ether);
    }

    function test_after_unlock_can_unprotect_then_transfer_standard_erc20() external {
        _createLockedProtectedLot(bob, 10 ether);

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(bobHot);
        ind.unprotect(10 ether);

        vm.prank(bobHot);
        assertTrue(ind.transfer(carol, 3 ether));
    }

    function test_allowance_cannot_bypass_locked_protected_domain() external {
        _createLockedProtectedLot(bob, 10 ether);

        vm.prank(bobHot);
        ind.approve(spender, type(uint256).max);

        vm.prank(spender);
        vm.expectRevert();
        ind.transferFrom(bob, genericContract, 1 ether);
    }
}
