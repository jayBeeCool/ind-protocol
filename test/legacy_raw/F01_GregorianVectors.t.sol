// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/lib/Gregorian.sol";

contract F01_GregorianVectors_Test is Test {
    function test_yearOf_epoch() public {
        assertEq(Gregorian.yearOf(0), 1970);
    }

    function test_leap_year_rules() public {
        // 1900 is NOT leap, 2000 is leap, 2100 is NOT leap
        assertTrue(!Gregorian.isLeap(1900));
        assertTrue(Gregorian.isLeap(2000));
        assertTrue(!Gregorian.isLeap(2100));
    }

    function test_yearStartTs_monotonic() public {
        uint256 y2024 = Gregorian.yearStartTs(2024);
        uint256 y2025 = Gregorian.yearStartTs(2025);
        assertLt(y2024, y2025);
    }
}
