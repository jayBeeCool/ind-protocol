// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InheritanceDollarVaultUpgradeable} from "../contracts/InheritanceDollarVaultUpgradeable.sol";
import {InheritanceDollarVaultUpgradeable} from "../contracts/InheritanceDollarVaultUpgradeable.sol";
import {MockINDKeyRegistryLite} from "./mocks/MockINDKeyRegistryLite.sol";

contract InheritanceDollarVaultUpgradeableBucketInvariantTest is Test {
    InheritanceDollarVaultUpgradeable internal ind;
    MockINDKeyRegistryLite internal reg;

    address internal admin = address(0xA11CE);
    address internal sale = address(0x5A1E);
    address internal alice = address(0xAAA1);
    address internal bob = address(0xBBB2);
    address internal bobHot = address(0xB0B01);
    address internal bobCold = address(0xB0B02);
    address internal carol = address(0xCCC3);
    address internal carolHot = address(0xC0C01);
    address internal carolCold = address(0xC0C02);
    address internal signing = address(0x1111);
    address internal revokeKey = address(0x2222);

    uint256 internal constant MAX_SUPPLY = 100_000_000_000 ether;

    function setUp() external {
        reg = new MockINDKeyRegistryLite();
        
        // Recipients of protected transfers must be explicitly protected-aware.
        reg.setOwnerKeys(bob, bobHot, bobCold);
        reg.setOwnerKeys(carol, carolHot, carolCold);
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

    function _activateAlice() internal {
        vm.prank(alice);
        assertTrue(ind.activateKeysAndMigrate(signing, revokeKey));
    }

    function test_skip_locked_bucket_and_use_next() external {
        vm.startPrank(alice);

        assertTrue(ind.protect(2 ether));
        assertTrue(ind.transferWithInheritance(bob, 1 ether, uint64(365 days), keccak256("LONG")));

        vm.warp(block.timestamp + 1 hours);

        assertTrue(ind.transferWithInheritance(bob, 1 ether, uint64(1 days), keccak256("SHORT")));

        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1 seconds);

        _assertBucketInvariant(bobHot);

        vm.prank(bobHot);
        assertTrue(ind.transferWithInheritance(carol, 1 ether, uint64(1 days), keccak256("SPEND")));

        assertEq(ind.protectedBalanceOf(bobHot), 1 ether);
        assertEq(ind.protectedBalanceOf(carolHot), 1 ether);

        _assertBucketInvariant(bobHot);
        _assertBucketInvariant(carolHot);
    }

    function test_partial_consumption_keeps_bucket_consistent() external {
        vm.startPrank(alice);

        assertTrue(ind.protect(10 ether));
        assertTrue(ind.transferWithInheritance(bob, 10 ether, uint64(1 days), keccak256("BOB")));

        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1 seconds);

        vm.prank(bobHot);
        assertTrue(ind.transferWithInheritance(carol, 4 ether, uint64(1 days), keccak256("SPEND4")));

        assertEq(ind.spendableBalanceOf(bobHot), 6 ether);
        assertEq(ind.protectedBalanceOf(bobHot), 6 ether);
        assertEq(ind.protectedBalanceOf(carolHot), 4 ether);

        _assertBucketInvariant(bobHot);
        _assertBucketInvariant(carolHot);
    }

    function test_revoke_updates_bucket_correctly() external {
        _activateAlice();

        vm.startPrank(signing);
        assertTrue(ind.protect(1 ether));
        assertTrue(ind.transferWithInheritance(bob, 1 ether, uint64(365 days), keccak256("LONG")));
        vm.stopPrank();

        assertEq(ind.protectedBalanceOf(bobHot), 1 ether);
        _assertBucketInvariant(bobHot);

        vm.prank(revokeKey);
        assertTrue(ind.revoke(bobHot, 0));

        assertEq(ind.protectedBalanceOf(bobHot), 0);
        assertEq(ind.unprotectedBalanceOf(signing), 1_000 ether);

        _assertBucketInvariant(bobHot);
        _assertBucketInvariant(signing);
    }

    function test_reduce_unlock_moves_bucket() external {
        _activateAlice();

        vm.startPrank(signing);
        assertTrue(ind.protect(1 ether));
        assertTrue(ind.transferWithInheritance(bob, 1 ether, uint64(365 days), keccak256("LONG")));
        vm.stopPrank();

        _assertBucketInvariant(bobHot);

        vm.prank(revokeKey);
        assertTrue(ind.reduceUnlockTime(bobHot, 0, _u64(block.timestamp + 1 days)));

        vm.warp(block.timestamp + 1 days + 1 seconds);

        _assertBucketInvariant(bobHot);

        vm.prank(bobHot);
        assertTrue(ind.transferWithInheritance(carol, 1 ether, uint64(1 days), keccak256("SPEND")));

        assertEq(ind.protectedBalanceOf(bobHot), 0);
        assertEq(ind.protectedBalanceOf(carolHot), 1 ether);

        _assertBucketInvariant(bobHot);
        _assertBucketInvariant(carolHot);
    }

    function test_many_buckets_gas_and_consistency() external {
        vm.prank(sale);
        ind.mint(alice, 100 ether);

        vm.prank(alice);
        assertTrue(ind.protect(50 ether));

        vm.startPrank(alice);
        for (uint256 i = 0; i < 50; i++) {
            assertTrue(ind.transferWithInheritance(bob, 1 ether, _u64(1 days + i * 1 hours), keccak256("BUCKET")));
        }
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 50 hours + 1 seconds);

        _assertBucketInvariant(bobHot);

        vm.prank(bobHot);
        assertTrue(ind.transferWithInheritance(carol, 50 ether, uint64(1 days), keccak256("SPEND50")));

        assertEq(ind.protectedBalanceOf(bobHot), 0);
        assertEq(ind.protectedBalanceOf(carolHot), 50 ether);

        _assertBucketInvariant(bobHot);
        _assertBucketInvariant(carolHot);
    }

    function testFuzz_bucket_invariant_after_mixed_operations(uint8 rawSteps) external {
        uint256 steps = 1 + (uint256(rawSteps) % 16);

        vm.prank(sale);
        ind.mint(bobHot, 100 ether);

        vm.startPrank(bobHot);

        for (uint256 i = 0; i < steps; i++) {
            assertTrue(ind.protect(1 ether));
            _assertBucketInvariant(bobHot);

            assertTrue(ind.transferWithInheritance(carol, 1 ether, _u64(1 days + i * 1 hours), keccak256("FUZZ")));
            _assertBucketInvariant(bobHot);
            _assertBucketInvariant(carolHot);
        }

        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + steps * 1 hours + 1 seconds);

        _assertBucketInvariant(carolHot);

        vm.startPrank(carolHot);
        for (uint256 i = 0; i < steps; i++) {
            assertTrue(ind.transferWithInheritance(bob, 1 ether, uint64(1 days), keccak256("BACK")));
            _assertBucketInvariant(carolHot);
            _assertBucketInvariant(bobHot);
        }
        vm.stopPrank();
    }
}
