// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/InheritanceDollar.sol";

contract F4F_ConsumeFuzz is Test {
    INDKeyRegistry reg;
    InheritanceDollar ind;

    address admin = address(0xA11CE);
    address alice = address(0xA);
    address bob   = address(0xB);
    address carl  = address(0xC);

    function setUp() public {
        reg = new INDKeyRegistry(admin);
        ind = new InheritanceDollar(admin, reg);
        vm.startPrank(admin);
        reg.grantRole(reg.REGISTRY_ADMIN_ROLE(), address(ind));
        vm.stopPrank();

        // Seed balances
        vm.prank(admin);
        ind.mint(alice, 200 ether);
        vm.prank(admin);
        ind.mint(bob, 50 ether);
    }

    function _inv(address who) internal view {
        uint256 b = ind.balanceOf(who);
        uint256 l = ind.lockedBalanceOf(who);
        uint256 s = ind.spendableBalanceOf(who);
        assertEq(b, l + s, "inv: balance != locked+spendable");
    }

    // Fuzz a sequence:
    // - Alice sends N lots to Bob with varying waits (>= 86400, <= 50y)
    // - time moves forward
    // - Bob attempts to spend part of his balance
    // We assert invariants and that locked cannot be spent early.
    function testFuzz_consume_never_spends_locked(
        uint8 nLots,
        uint32 tJump1,
        uint32 tJump2,
        uint96 sendAmtRaw,
        uint96 spendAmtRaw
    ) public {
        // bound inputs
        uint256 N = bound(uint256(nLots), 1, 25);
        uint256 sendAmt = bound(uint256(sendAmtRaw), 1 ether, 5 ether);
        uint256 spendAmt = bound(uint256(spendAmtRaw), 1, 30 ether);

        // create lots with mixed waits: some 1d, some bigger
        for (uint256 i = 0; i < N; i++) {
            uint64 w = uint64(86400 + (i % 5) * 3600); // 1d .. 1d+4h
            vm.prank(alice);
            ind.transferWithInheritance(bob, sendAmt, w, bytes32(uint256(i)));
            _inv(alice);
            _inv(bob);
        }

        // Before unlock window: Bob cannot spend what is still locked.
        // Jump less than 1 day in first warp (0..20h)
        uint256 j1 = bound(uint256(tJump1), 0, 20 hours);
        vm.warp(block.timestamp + j1);

        // If bob tries to spend > spendable, must revert.
        uint256 spendableNow = ind.spendableBalanceOf(bob);
        if (spendAmt > spendableNow) {
            vm.prank(bob);
            vm.expectRevert(bytes("insufficient-spendable"));
            ind.transfer(carl, spendAmt);
        }

        _inv(bob);

        // Warp forward enough that at least base 1d lots unlock (1d + up to 4h)
        uint256 j2 = bound(uint256(tJump2), 1 days, 3 days);
        vm.warp(block.timestamp + j2);

        // Now spending up to spendable must succeed
        uint256 spendable2 = ind.spendableBalanceOf(bob);
        uint256 toSpend = spendAmt;
        if (toSpend > spendable2) toSpend = spendable2;

        if (toSpend > 0) {
            vm.prank(bob);
            assertTrue(ind.transfer(carl, toSpend));
        }

        _inv(bob);
        _inv(carl);
    }
}
