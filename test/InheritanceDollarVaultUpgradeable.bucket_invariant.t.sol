// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InheritanceDollarVaultUpgradeable} from "../contracts/InheritanceDollarVaultUpgradeable.sol";
import {InheritanceDollarVaultUpgradeableV2} from "../contracts/InheritanceDollarVaultUpgradeableV2.sol";
import {MockINDKeyRegistryLite} from "./mocks/MockINDKeyRegistryLite.sol";

contract InheritanceDollarVaultUpgradeableV2BucketInvariantTest is Test {
    InheritanceDollarVaultUpgradeableV2 internal ind;
    MockINDKeyRegistryLite internal reg;

    address internal admin = address(0xA11CE);
    address internal sale = address(0x5A1E);
    address internal alice = address(0xAAA1);
    address internal bob = address(0xBBB2);
    address internal carol = address(0xCCC3);
    address internal signing = address(0x1111);
    address internal revokeKey = address(0x2222);

    uint256 internal constant MAX_SUPPLY = 100_000_000_000 ether;

    function setUp() external {
        reg = new MockINDKeyRegistryLite();
        InheritanceDollarVaultUpgradeableV2 impl = new InheritanceDollarVaultUpgradeableV2();

        bytes memory initData =
            abi.encodeCall(InheritanceDollarVaultUpgradeableV2.initialize, (admin, MAX_SUPPLY, address(reg)));

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        ind = InheritanceDollarVaultUpgradeableV2(address(proxy));

        vm.startPrank(admin);
        ind.grantRole(ind.MINTER_ROLE(), sale);
        vm.stopPrank();

        vm.prank(sale);
        ind.mint(alice, 1_000 ether);
    }

    function _u64(uint256 x) internal pure returns (uint64) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint64(x);
    }

    function _assertBucketInvariant(address user) internal view {
        (
            uint256 bucketTotal,
            uint256 linkedLotTotal,
            uint256 spendable,
            uint256 locked,
            uint256 bucketCount
        ) = ind.bucketDebugTotals(user);

        uint256 protectedBalance = ind.protectedBalanceOf(user);

        assertEq(bucketTotal, protectedBalance, "bucketTotal != protectedBalance");
        assertEq(linkedLotTotal, protectedBalance, "linkedLotTotal != protectedBalance");
        assertEq(spendable, ind.spendableBalanceOf(user), "bucket spendable != public spendable");
        assertEq(locked, ind.lockedBalanceOf(user), "bucket locked != public locked");

        if (protectedBalance == 0) {
            assertEq(bucketCount, 0, "empty protected but non-empty buckets");
        }
    }

    function _activateAlice() internal {
        vm.prank(alice);
        assertTrue(ind.activateKeysAndMigrate(signing, revokeKey));
    }

    function test_skip_locked_bucket_and_use_next() external {
        vm.startPrank(alice);

        assertTrue(ind.protect(2 ether));
        assertTrue(ind.transferWithInheritance(bob, 1 ether, uint64(365 days), bytes32("LONG")));

        vm.warp(block.timestamp + 1 hours);

        assertTrue(ind.transferWithInheritance(bob, 1 ether, uint64(1 days), bytes32("SHORT")));

        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1 seconds);

        _assertBucketInvariant(bob);

        vm.prank(bob);
        assertTrue(ind.transferWithInheritance(carol, 1 ether, uint64(1 days), bytes32("SPEND")));

        assertEq(ind.protectedBalanceOf(bob), 1 ether);
        assertEq(ind.protectedBalanceOf(carol), 1 ether);

        _assertBucketInvariant(bob);
        _assertBucketInvariant(carol);
    }

    function test_partial_consumption_keeps_bucket_consistent() external {
        vm.startPrank(alice);

        assertTrue(ind.protect(10 ether));
        assertTrue(ind.transferWithInheritance(bob, 10 ether, uint64(1 days), bytes32("BOB")));

        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1 seconds);

        vm.prank(bob);
        assertTrue(ind.transferWithInheritance(carol, 4 ether, uint64(1 days), bytes32("SPEND4")));

        assertEq(ind.spendableBalanceOf(bob), 6 ether);
        assertEq(ind.protectedBalanceOf(bob), 6 ether);
        assertEq(ind.protectedBalanceOf(carol), 4 ether);

        _assertBucketInvariant(bob);
        _assertBucketInvariant(carol);
    }

    function test_revoke_updates_bucket_correctly() external {
        _activateAlice();

        vm.startPrank(signing);
        assertTrue(ind.protect(1 ether));
        assertTrue(ind.transferWithInheritance(bob, 1 ether, uint64(365 days), bytes32("LONG")));
        vm.stopPrank();

        assertEq(ind.protectedBalanceOf(bob), 1 ether);
        _assertBucketInvariant(bob);

        vm.prank(revokeKey);
        assertTrue(ind.revoke(bob, 0));

        assertEq(ind.protectedBalanceOf(bob), 0);
        assertEq(ind.unprotectedBalanceOf(signing), 1_000 ether);

        _assertBucketInvariant(bob);
        _assertBucketInvariant(signing);
    }

    function test_reduce_unlock_moves_bucket() external {
        _activateAlice();

        vm.startPrank(signing);
        assertTrue(ind.protect(1 ether));
        assertTrue(ind.transferWithInheritance(bob, 1 ether, uint64(365 days), bytes32("LONG")));
        vm.stopPrank();

        _assertBucketInvariant(bob);

        vm.prank(revokeKey);
        assertTrue(ind.reduceUnlockTime(bob, 0, _u64(block.timestamp + 1 days)));

        vm.warp(block.timestamp + 1 days + 1 seconds);

        _assertBucketInvariant(bob);

        vm.prank(bob);
        assertTrue(ind.transferWithInheritance(carol, 1 ether, uint64(1 days), bytes32("SPEND")));

        assertEq(ind.protectedBalanceOf(bob), 0);
        assertEq(ind.protectedBalanceOf(carol), 1 ether);

        _assertBucketInvariant(bob);
        _assertBucketInvariant(carol);
    }

    function test_lazy_migration_from_old_proxy_state_does_not_break_spend() external {
        MockINDKeyRegistryLite reg2 = new MockINDKeyRegistryLite();
        InheritanceDollarVaultUpgradeable oldImpl = new InheritanceDollarVaultUpgradeable();

        bytes memory initData =
            abi.encodeCall(InheritanceDollarVaultUpgradeable.initialize, (admin, MAX_SUPPLY, address(reg2)));

        ERC1967Proxy proxy = new ERC1967Proxy(address(oldImpl), initData);
        InheritanceDollarVaultUpgradeable oldInd = InheritanceDollarVaultUpgradeable(address(proxy));

        vm.startPrank(admin);
        oldInd.grantRole(oldInd.MINTER_ROLE(), sale);
        vm.stopPrank();

        vm.prank(sale);
        oldInd.mint(alice, 10 ether);

        vm.startPrank(alice);
        assertTrue(oldInd.protect(2 ether));
        assertTrue(oldInd.transferWithInheritance(bob, 1 ether, uint64(365 days), bytes32("LONG")));

        vm.warp(block.timestamp + 1 hours);

        assertTrue(oldInd.transferWithInheritance(bob, 1 ether, uint64(1 days), bytes32("SHORT")));
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1 seconds);

        InheritanceDollarVaultUpgradeableV2 newImpl = new InheritanceDollarVaultUpgradeableV2();

        vm.prank(admin);
        oldInd.upgradeToAndCall(address(newImpl), "");

        InheritanceDollarVaultUpgradeableV2 upgraded = InheritanceDollarVaultUpgradeableV2(address(proxy));

        upgraded.migrateLotsFor(bob, 1);

        vm.prank(bob);
        assertTrue(upgraded.transferWithInheritance(carol, 1 ether, uint64(1 days), bytes32("SPEND")));

        assertEq(upgraded.protectedBalanceOf(bob), 1 ether);
        assertEq(upgraded.protectedBalanceOf(carol), 1 ether);

        (
            uint256 bucketTotal,
            uint256 linkedLotTotal,
            uint256 spendable,
            uint256 locked,
            uint256 bucketCount
        ) = upgraded.bucketDebugTotals(bob);

        assertEq(bucketTotal, upgraded.protectedBalanceOf(bob));
        assertEq(linkedLotTotal, upgraded.protectedBalanceOf(bob));
        assertEq(spendable, upgraded.spendableBalanceOf(bob));
        assertEq(locked, upgraded.lockedBalanceOf(bob));
        assertGt(bucketCount, 0);
    }

    function test_many_buckets_gas_and_consistency() external {
        vm.prank(sale);
        ind.mint(alice, 100 ether);

        vm.prank(alice);
        assertTrue(ind.protect(50 ether));

        vm.startPrank(alice);
        for (uint256 i = 0; i < 50; i++) {
            assertTrue(ind.transferWithInheritance(bob, 1 ether, _u64(1 days + i * 1 hours), bytes32("BUCKET")));
        }
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 50 hours + 1 seconds);

        _assertBucketInvariant(bob);

        vm.prank(bob);
        assertTrue(ind.transferWithInheritance(carol, 50 ether, uint64(1 days), bytes32("SPEND50")));

        assertEq(ind.protectedBalanceOf(bob), 0);
        assertEq(ind.protectedBalanceOf(carol), 50 ether);

        _assertBucketInvariant(bob);
        _assertBucketInvariant(carol);
    }

    function testFuzz_bucket_invariant_after_mixed_operations(uint8 rawSteps) external {
        uint256 steps = 1 + (uint256(rawSteps) % 16);

        vm.prank(sale);
        ind.mint(bob, 100 ether);

        vm.startPrank(bob);

        for (uint256 i = 0; i < steps; i++) {
            assertTrue(ind.protect(1 ether));
            _assertBucketInvariant(bob);

            assertTrue(ind.transferWithInheritance(carol, 1 ether, _u64(1 days + i * 1 hours), bytes32("FUZZ")));
            _assertBucketInvariant(bob);
            _assertBucketInvariant(carol);
        }

        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + steps * 1 hours + 1 seconds);

        _assertBucketInvariant(carol);

        vm.startPrank(carol);
        for (uint256 i = 0; i < steps; i++) {
            assertTrue(ind.transferWithInheritance(alice, 1 ether, uint64(1 days), bytes32("BACK")));
            _assertBucketInvariant(carol);
            _assertBucketInvariant(alice);
        }
        vm.stopPrank();
    }
}
