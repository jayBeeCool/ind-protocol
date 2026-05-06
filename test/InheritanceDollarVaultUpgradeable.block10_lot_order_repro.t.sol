// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InheritanceDollarVaultUpgradeable} from "../contracts/InheritanceDollarVaultUpgradeable.sol";
import {MockINDKeyRegistryLite} from "./mocks/MockINDKeyRegistryLite.sol";

contract InheritanceDollarVaultUpgradeableLotOrderReproTest is Test {
    InheritanceDollarVaultUpgradeable internal ind;
    MockINDKeyRegistryLite internal reg;

    address internal admin = address(0xA11CE);
    address internal sale = address(0x5A1E);
    address internal alice = address(0xAAA1);
    address internal bob = address(0xBBB2);
    address internal carol = address(0xCCC3);

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

        vm.prank(sale);
        ind.mint(alice, 1_000 ether);
    }

    /*
     * CASO A:
     * 1) Alice manda a Bob 1 IND protected con scadenza lunga.
     * 2) Dopo 1 ora Alice manda a Bob 1 IND protected con scadenza corta.
     * 3) Dopo la scadenza corta Bob deve poter spendere quello scaduto,
     *    anche se prima in array c'è il lot lungo ancora locked.
     */
    function test_received_locked_first_received_unlocked_later_must_be_spendable() external {
        vm.startPrank(alice);

        assertTrue(ind.protect(2 ether));

        assertTrue(ind.transferWithInheritance(bob, 1 ether, uint64(365 days), keccak256("LONG")));

        vm.warp(block.timestamp + 1 hours);

        assertTrue(ind.transferWithInheritance(bob, 1 ether, uint64(1 days), keccak256("SHORT")));

        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1 seconds);

        assertEq(ind.protectedBalanceOf(bob), 2 ether);
        assertEq(ind.lockedBalanceOf(bob), 1 ether);
        assertEq(ind.spendableBalanceOf(bob), 1 ether);

        vm.prank(bob);
        assertTrue(ind.transferWithInheritance(carol, 1 ether, uint64(1 days), keccak256("BOB_SPENDS_SHORT")));

        assertEq(ind.protectedBalanceOf(bob), 1 ether);
        assertEq(ind.protectedBalanceOf(carol), 1 ether);
    }

    /*
     * CASO B:
     * 1) Bob riceve 1 IND protected con scadenza lunga.
     * 2) Bob riceve/mantiene IND unprotected.
     * 3) Bob converte 1 IND unprotected in protected con protect().
     * 4) Quel nuovo lot è immediately spendable.
     * 5) Bob deve poter spendere quel lot subito, anche se prima c'è il lot lungo locked.
     */
    function test_received_locked_first_self_protect_later_must_be_immediately_spendable() external {
        vm.startPrank(alice);

        assertTrue(ind.protect(1 ether));
        assertTrue(ind.transferWithInheritance(bob, 1 ether, uint64(365 days), keccak256("LONG")));

        vm.stopPrank();

        vm.prank(sale);
        ind.mint(bob, 1 ether);

        vm.prank(bob);
        assertTrue(ind.protect(1 ether));

        assertEq(ind.protectedBalanceOf(bob), 2 ether);
        assertEq(ind.lockedBalanceOf(bob), 1 ether);
        assertEq(ind.spendableBalanceOf(bob), 1 ether);

        vm.prank(bob);
        assertTrue(ind.transferWithInheritance(carol, 1 ether, uint64(1 days), keccak256("BOB_SPENDS_SELF_PROTECT")));

        assertEq(ind.protectedBalanceOf(bob), 1 ether);
        assertEq(ind.protectedBalanceOf(carol), 1 ether);
    }
}
