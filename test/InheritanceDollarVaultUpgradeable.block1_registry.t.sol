// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InheritanceDollarVaultUpgradeable} from "../contracts/InheritanceDollarVaultUpgradeable.sol";
import {MockINDKeyRegistryLite} from "./mocks/MockINDKeyRegistryLite.sol";

contract InheritanceDollarVaultUpgradeableBlock1RegistryTest is Test {
    InheritanceDollarVaultUpgradeable internal ind;
    MockINDKeyRegistryLite internal reg;

    address internal admin = address(0xA11CE);
    address internal sale = address(0x5A1E);
    address internal alice = address(0xAAA1);
    address internal bob = address(0xBBB2);
    address internal carol = address(0xCCC3);
    address internal signing = address(0x1111);

    uint256 internal constant MAX_SUPPLY = 100_000_000_000 ether;

    function setUp() external {
        reg = new MockINDKeyRegistryLite();
        InheritanceDollarVaultUpgradeable impl = new InheritanceDollarVaultUpgradeable();

        bytes memory initData =
            abi.encodeCall(InheritanceDollarVaultUpgradeable.initialize, (admin, MAX_SUPPLY, address(reg)));

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        ind = InheritanceDollarVaultUpgradeable(address(proxy));

        vm.startPrank(admin);
        ind.grantRole(ind.MINTER_ROLE(), sale);
        vm.stopPrank();

        vm.startPrank(sale);
        ind.mint(alice, 100 ether);
        ind.mint(bob, 100 ether);
        vm.stopPrank();
    }

    function test_owner_disabled_reverts_transfer() external {
        reg.setOwnerKeys(alice, signing);

        vm.prank(alice);
        vm.expectRevert(bytes4(0xf28dceb3));
        ind.transfer(bob, 1 ether);
    }

    function test_owner_disabled_reverts_approve() external {
        reg.setOwnerKeys(alice, signing);

        vm.prank(alice);
        vm.expectRevert(bytes4(0xf28dceb3));
        ind.approve(bob, 1 ether);
    }

    function test_owner_disabled_reverts_transferWithInheritance() external {
        vm.prank(alice);
        assertTrue(ind.protect(10 ether));

        reg.setOwnerKeys(alice, signing);

        vm.prank(alice);
        vm.expectRevert(bytes4(0xf28dceb3));
        ind.transferWithInheritance(bob, 1 ether, uint64(1 days), bytes32(0));
    }

    function test_owner_disabled_reverts_transferFrom_when_from_is_disabled() external {
        reg.setOwnerKeys(alice, signing);

        vm.prank(alice);
        vm.expectRevert(bytes4(0xf28dceb3));
        ind.approve(bob, 10 ether);
    }

    function test_transfer_redirects_to_signing_key_if_recipient_owner_disabled() external {
        reg.setOwnerKeys(carol, signing);

        vm.prank(alice);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        assertTrue(ind.transfer(carol, 5 ether));

        assertEq(ind.balanceOf(carol), 0);
        assertEq(ind.balanceOf(signing), 5 ether);
    }

    function test_mint_redirects_to_signing_key_if_recipient_owner_disabled() external {
        reg.setOwnerKeys(carol, signing);

        vm.prank(sale);
        ind.mint(carol, 7 ether);

        assertEq(ind.balanceOf(carol), 0);
        assertEq(ind.balanceOf(signing), 7 ether);
    }

    function test_protected_transfer_redirects_to_signing_key_if_recipient_owner_disabled() external {
        reg.setOwnerKeys(carol, signing);

        vm.prank(alice);
        assertTrue(ind.protect(20 ether));

        vm.prank(alice);
        assertTrue(ind.transferWithInheritance(carol, 8 ether, uint64(1 days), bytes32(0)));

        assertEq(ind.protectedBalanceOf(carol), 0);
        assertEq(ind.protectedBalanceOf(signing), 8 ether);
    }

    function test_signing_key_updates_lastInteraction_for_logical_owner() external {
        reg.setOwnerKeys(alice, signing);

        vm.prank(sale);
        ind.mint(signing, 5 ether);

        uint64 beforeTs = ind.lastInteractionOf(alice);

        vm.warp(block.timestamp + 10);
        vm.prank(signing);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        assertTrue(ind.transfer(bob, 1 ether));

        uint64 afterTs = ind.lastInteractionOf(alice);
        assertGt(afterTs, beforeTs);
    }
}
