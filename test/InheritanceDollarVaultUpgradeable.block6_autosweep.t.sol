// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../contracts/InheritanceDollarVaultUpgradeable.sol";
import "./mocks/MockINDKeyRegistryLite.sol";

contract InheritanceDollarVaultUpgradeableBlock6AutoSweepTest is Test {
    InheritanceDollarVaultUpgradeable internal ind;
    MockINDKeyRegistryLite internal reg;

    address internal admin = address(0xA11CE);
    address internal sale = address(0x5A1E);
    address internal alice = address(0xAAA1);
    address internal bob = address(0xBBB2);
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

        vm.startPrank(sale);
        ind.mint(alice, 100 ether);
        ind.mint(bob, 1 ether);
        vm.stopPrank();

        // inizializza la liveness di Bob
        vm.prank(bob);
        ind.transfer(admin, 1 ether);
    }

    function _prepareLotToBob() internal {
        vm.prank(alice);
        ind.protect(40 ether);

        vm.prank(alice);
        ind.transferWithInheritance(bob, 25 ether, uint64(1 days), bytes32(0));
    }

    function test_autoSweepIfDead_moves_unlocked_lots_to_heir() external {
        _prepareLotToBob();

        vm.prank(bob);
        ind.setDefaultHeir(dave);

        vm.warp(block.timestamp + 1 days + 1);
        uint64 deathTs = ind.deathTimestampOf(bob);
        vm.warp(deathTs + 1);

        uint256 swept = ind.autoSweepIfDead(bob);

        assertEq(swept, 25 ether);
        assertEq(ind.balanceOf(dave), 25 ether);
        assertEq(ind.protectedBalanceOf(bob), 0);
    }

    function test_incoming_transfer_to_dead_owner_bounces_back_to_sender_after_auto_sweep() external {
        _prepareLotToBob();

        vm.prank(bob);
        ind.setDefaultHeir(dave);

        vm.warp(block.timestamp + 1 days + 1);
        uint64 deathTs = ind.deathTimestampOf(bob);
        vm.warp(deathTs + 1);

        uint256 aliceBefore = ind.balanceOf(alice);
        vm.prank(alice);
        ind.transfer(bob, 1 ether);

        // vecchi fondi del morto -> heir
        assertEq(ind.balanceOf(dave), 25 ether);

        // nuovo invio -> resta al mittente
        assertEq(ind.balanceOf(alice), aliceBefore);
        assertEq(ind.balanceOf(bob), 0);
        assertEq(ind.protectedBalanceOf(bob), 0);
    }

    function test_incoming_transfer_to_dead_owner_with_no_heir_bounces_back_to_sender_and_old_funds_burn() external {
        _prepareLotToBob();

        uint256 tsBefore = ind.totalSupply();
        uint256 aliceBefore = ind.balanceOf(alice);

        vm.warp(block.timestamp + 1 days + 1);
        uint64 deathTs = ind.deathTimestampOf(bob);
        vm.warp(deathTs + 1);

        vm.prank(alice);
        ind.transfer(bob, 1 ether);

        // vecchi fondi del morto -> burn
        assertEq(ind.totalSupply(), tsBefore - 25 ether);

        // nuovo invio -> resta al mittente
        assertEq(ind.balanceOf(alice), aliceBefore);
        assertEq(ind.balanceOf(bob), 0);
        assertEq(ind.protectedBalanceOf(bob), 0);
    }
}
