// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./InheritanceDollar.t.sol";

contract F01_R25_R27_GregorianTrigger is InheritanceDollarTest {
    function _setupLotToBob(uint64 waitSeconds) internal returns (uint256 lotIndex) {
        vm.prank(admin);
        ind.mint(alice, 10 ether);

        vm.prank(alice);
        ind.transferWithInheritance(bob, 5 ether, waitSeconds, bytes32(0));

        return 0; // first lot for bob
    }

    function _unlockOf(address who, uint256 lotIndex) internal view returns (uint64) {
        (,, uint64 unlockTime,,) = ind.lotOf(who, lotIndex);
        return unlockTime;
    }

    function test_reduce_boundary_365days_allowed_secondsMode() public {
        uint256 lotIndex = _setupLotToBob(uint64(400 days));

        uint64 unlockBefore = _unlockOf(bob, lotIndex);
        uint64 newUnlock = unlockBefore - uint64(365 days);

        vm.prank(alice);
        ind.reduceUnlockTime(bob, lotIndex, newUnlock);

        uint64 unlockAfter = _unlockOf(bob, lotIndex);
        assertEq(unlockAfter, newUnlock);
    }

    function test_reduce_boundary_365days_plus1_calendarMode_still_reduces() public {
        uint256 lotIndex = _setupLotToBob(uint64(400 days));

        uint64 unlockBefore = _unlockOf(bob, lotIndex);
        uint64 newUnlock = unlockBefore - uint64(365 days + 1);

        vm.prank(alice);
        ind.reduceUnlockTime(bob, lotIndex, newUnlock);

        uint64 unlockAfter = _unlockOf(bob, lotIndex);
        assertTrue(unlockAfter < unlockBefore);
    }
}
