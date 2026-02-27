// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./InheritanceDollar.t.sol";

contract F2_Liveness_AND_Test is InheritanceDollarTest {
    function _setupOwnerWithKeys(address owner, address sk, address rk, address heir) internal {
        vm.prank(owner);
        ind.activateKeysAndMigrateWithHeir(sk, rk, heir);
    }

    function test_liveness_AND_spend_recent_blocks_death_even_if_renew_old() public {
        // owners + keys
        address sOwner = address(0xAA01);
        address sSK = address(0xAA02);
        address sRK = address(0xAA03);

        address rOwner = address(0xBB01);
        address rSK = address(0xBB02);
        address rRK = address(0xBB03);

        // init
        _setupOwnerWithKeys(sOwner, sSK, sRK, address(0));
        _setupOwnerWithKeys(rOwner, rSK, rRK, address(0));

        // fund sender + recipient signing keys
        vm.prank(admin);
        ind.mint(sSK, 50 ether);
        vm.prank(admin);
        ind.mint(rSK, 2 ether);

        // touch BOTH clocks at t0 via outgoing tx from both signing keys
        vm.prank(sSK);
        assertTrue(ind.transfer(address(0xD00D), 1));
        vm.prank(rSK);
        assertTrue(ind.transfer(address(0xD00D), 1));

        // create a locked lot to recipient signing key

        uint64 wait = uint64(ind.MIN_WAIT_SECONDS());
        vm.prank(sSK);
        ind.transferWithInheritance(rSK, 10 ether, wait, bytes32("X"));
        uint256 lotIndex = ind.getLots(rSK).length - 1;

        // Move close to 7y: let "renew" become old (we do NOT call keepAlive)
        // but refresh spend at year 6 (outgoing tx)
        vm.warp(block.timestamp + (uint256(ind.DEAD_AFTER_SECONDS()) - 365 days)); // ~6y
        vm.prank(rSK);
        assertTrue(ind.transfer(address(0xD00D), 1)); // spend refreshed near 6y

        // Now go just beyond 7y from t0: renew likely expired, spend NOT expired => must NOT be dead
        vm.warp(block.timestamp + 365 days + 1);

        // unlock also passed long ago, sweep should NOT burn; it should keep value in recipient (not reduce totalSupply)
        uint256 supplyBefore = ind.totalSupply();
        uint256 rBefore = ind.balanceOf(rSK);

        vm.expectRevert(bytes("recipient-alive"));
        ind.sweepLot(rSK, lotIndex);

        // state unchanged (implicit by revert)
        assertEq(ind.totalSupply(), supplyBefore);
        assertEq(ind.balanceOf(rSK), rBefore);
    }

    function test_liveness_AND_renew_recent_blocks_death_even_if_spend_old() public {
        // owners + keys
        address sOwner = address(0xCC01);
        address sSK = address(0xCC02);
        address sRK = address(0xCC03);

        address rOwner = address(0xDD01);
        address rSK = address(0xDD02);
        address rRK = address(0xDD03);

        _setupOwnerWithKeys(sOwner, sSK, sRK, address(0));
        _setupOwnerWithKeys(rOwner, rSK, rRK, address(0));

        vm.prank(admin);
        ind.mint(sSK, 50 ether);
        vm.prank(admin);
        ind.mint(rSK, 2 ether);

        // Touch spend at t0 for both
        vm.prank(sSK);
        assertTrue(ind.transfer(address(0xD00D), 1));
        vm.prank(rSK);
        assertTrue(ind.transfer(address(0xD00D), 1));

        uint64 wait = uint64(ind.MIN_WAIT_SECONDS());
        vm.prank(sSK);
        ind.transferWithInheritance(rSK, 9 ether, wait, bytes32("Y"));
        uint256 lotIndex = ind.getLots(rSK).length - 1;

        // Make spend old: go to just beyond 7y, but refresh "renew" right before (keepAlive / avg tick).
        // Prefer keepAlive() if exists; fallback to a zero-amount self-transfer if protocol uses that for renew (should not),
        // otherwise this test will fail and you incolli i simboli disponibili.
        vm.warp(block.timestamp + uint256(ind.DEAD_AFTER_SECONDS()) - 1);
        // refresh RENEW on the recipient owner via its signing key
        vm.prank(rSK);
        ind.keepAlive();
        // Now go beyond 7y: spend expired, renew NOT expired => must NOT be dead
        vm.warp(block.timestamp + 2);

        uint256 supplyBefore = ind.totalSupply();
        vm.expectRevert(bytes("recipient-alive"));
        ind.sweepLot(rSK, lotIndex);
        assertEq(ind.totalSupply(), supplyBefore);
    }
}
