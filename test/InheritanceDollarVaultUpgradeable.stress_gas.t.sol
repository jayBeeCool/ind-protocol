// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InheritanceDollarVaultUpgradeable} from "../contracts/InheritanceDollarVaultUpgradeable.sol";
import {MockINDKeyRegistryLite} from "./mocks/MockINDKeyRegistryLite.sol";

contract InheritanceDollarVaultUpgradeableStressGasTest is Test {
    InheritanceDollarVaultUpgradeable internal ind;
    MockINDKeyRegistryLite internal reg;

    address internal admin = address(0xA11CE);
    address internal sale = address(0x5A1E);
    address internal alice = address(0xAAA1);
    address internal bob = address(0xBBB2);
    address internal carol = address(0xCCC3);
    address internal dave = address(0xDDD4);

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
        ind.mint(alice, 100_000 ether);
    }

    function _u64(uint256 x) internal pure returns (uint64) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint64(x);
    }

    function _assertBucketInvariant(address user) internal view {
        InheritanceDollarVaultUpgradeable.Lot[] memory lots = ind.getLots(user);

        uint256 protectedFromLots;
        uint256 spendableFromLots;
        uint256 lockedFromLots;

        for (uint256 i = ind.headOf(user); i < lots.length; i++) {
            protectedFromLots += lots[i].amount;

            if (block.timestamp >= lots[i].unlockTime) {
                spendableFromLots += lots[i].amount;
            } else {
                lockedFromLots += lots[i].amount;
            }
        }

        assertEq(protectedFromLots, ind.protectedBalanceOf(user), "lots total != protectedBalance");
        assertEq(spendableFromLots, ind.spendableBalanceOf(user), "lots spendable != public spendable");
        assertEq(lockedFromLots, ind.lockedBalanceOf(user), "lots locked != public locked");
    }

    function test_stress_250_increasing_buckets_consume_all() external {
        vm.prank(alice);
        assertTrue(ind.protect(250 ether));

        vm.startPrank(alice);
        for (uint256 i = 0; i < 250; i++) {
            assertTrue(ind.transferWithInheritance(bob, 1 ether, _u64(1 days + i * 1 hours), keccak256("INC")));
        }
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 250 hours + 1 seconds);

        _assertBucketInvariant(bob);

        uint256 gasBefore = gasleft();
        vm.prank(bob);
        assertTrue(ind.transferWithInheritance(carol, 250 ether, uint64(1 days), keccak256("SPEND250")));
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("gas_consume_250_buckets", gasUsed);

        assertEq(ind.protectedBalanceOf(bob), 0);
        assertEq(ind.protectedBalanceOf(carol), 250 ether);

        _assertBucketInvariant(bob);
        _assertBucketInvariant(carol);
    }

    function test_stress_reverse_insert_80_buckets_then_consume_all() external {
        vm.prank(alice);
        assertTrue(ind.protect(80 ether));

        vm.startPrank(alice);
        for (uint256 i = 80; i > 0; i--) {
            assertTrue(ind.transferWithInheritance(bob, 1 ether, _u64(1 days + i * 1 hours), keccak256("REV")));
        }
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 81 hours);

        _assertBucketInvariant(bob);

        uint256 gasBefore = gasleft();
        vm.prank(bob);
        assertTrue(ind.transferWithInheritance(carol, 80 ether, uint64(1 days), keccak256("SPEND80")));
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("gas_reverse_insert_consume_80", gasUsed);

        assertEq(ind.protectedBalanceOf(bob), 0);
        assertEq(ind.protectedBalanceOf(carol), 80 ether);

        _assertBucketInvariant(bob);
        _assertBucketInvariant(carol);
    }

    function test_stress_many_lots_same_bucket_partial_then_full() external {
        vm.prank(alice);
        assertTrue(ind.protect(100 ether));

        vm.startPrank(alice);
        for (uint256 i = 0; i < 100; i++) {
            assertTrue(ind.transferWithInheritance(bob, 1 ether, uint64(1 days), keccak256("SAME")));
        }
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1 seconds);

        _assertBucketInvariant(bob);

        uint256 gasBefore = gasleft();
        vm.prank(bob);
        assertTrue(ind.transferWithInheritance(carol, 40 ether, uint64(1 days), keccak256("PARTIAL")));
        uint256 gasUsedPartial = gasBefore - gasleft();

        emit log_named_uint("gas_same_bucket_partial_40_of_100", gasUsedPartial);

        assertEq(ind.protectedBalanceOf(bob), 60 ether);
        assertEq(ind.protectedBalanceOf(carol), 40 ether);

        _assertBucketInvariant(bob);
        _assertBucketInvariant(carol);

        gasBefore = gasleft();
        vm.prank(bob);
        assertTrue(ind.transferWithInheritance(dave, 60 ether, uint64(1 days), keccak256("REST")));
        uint256 gasUsedRest = gasBefore - gasleft();

        emit log_named_uint("gas_same_bucket_rest_60", gasUsedRest);

        assertEq(ind.protectedBalanceOf(bob), 0);
        assertEq(ind.protectedBalanceOf(dave), 60 ether);

        _assertBucketInvariant(bob);
        _assertBucketInvariant(dave);
    }

    function test_stress_interleaved_multi_user() external {
        vm.prank(sale);
        ind.mint(bob, 500 ether);

        vm.prank(alice);
        assertTrue(ind.protect(300 ether));

        vm.prank(bob);
        assertTrue(ind.protect(300 ether));

        vm.startPrank(alice);
        for (uint256 i = 0; i < 75; i++) {
            assertTrue(ind.transferWithInheritance(carol, 1 ether, _u64(1 days + i * 1 hours), keccak256("A")));
        }
        vm.stopPrank();

        vm.startPrank(bob);
        for (uint256 i = 0; i < 75; i++) {
            assertTrue(ind.transferWithInheritance(dave, 1 ether, _u64(1 days + i * 2 hours), keccak256("B")));
        }
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 150 hours + 1 seconds);

        _assertBucketInvariant(carol);
        _assertBucketInvariant(dave);

        vm.prank(carol);
        assertTrue(ind.transferWithInheritance(alice, 75 ether, uint64(1 days), keccak256("BACKA")));

        vm.prank(dave);
        assertTrue(ind.transferWithInheritance(bob, 75 ether, uint64(1 days), keccak256("BACKB")));

        _assertBucketInvariant(alice);
        _assertBucketInvariant(bob);
        _assertBucketInvariant(carol);
        _assertBucketInvariant(dave);
    }

    function test_gas_single_append_after_fast_path() external {
        vm.prank(alice);
        assertTrue(ind.protect(10 ether));

        vm.startPrank(alice);

        uint256 gasBefore = gasleft();
        assertTrue(ind.transferWithInheritance(bob, 1 ether, uint64(1 days), keccak256("B1")));
        uint256 gasFirst = gasBefore - gasleft();

        gasBefore = gasleft();
        assertTrue(ind.transferWithInheritance(bob, 1 ether, uint64(2 days), keccak256("B2")));
        uint256 gasAppend = gasBefore - gasleft();

        vm.stopPrank();

        emit log_named_uint("gas_first_bucket_insert", gasFirst);
        emit log_named_uint("gas_fast_tail_append", gasAppend);

        _assertBucketInvariant(bob);
    }
}
