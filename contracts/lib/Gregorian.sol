// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal Gregorian helper for UTC year extraction.
/// @dev Algorithm based on civil-from-days (proleptic Gregorian calendar).
library Gregorian {
    
    // IND compatibility: extension method used by token (uint256(ts).yearOf()).
    function yearOf(uint256 ts) internal pure returns (uint16) {
        return uint16(yearFromTimestamp(ts));
    
    /// @notice Returns true if `y` is a leap year in Gregorian calendar.
    function isLeapYear(uint16 y) internal pure returns (bool) {
        if (y % 4 != 0) return false;
        if (y % 100 != 0) return true;
        return (y % 400 == 0);
    }

    /// @notice Days in month for Gregorian calendar.
    function daysInMonth(uint16 y, uint8 m) internal pure returns (uint8) {
        if (m == 1 || m == 3 || m == 5 || m == 7 || m == 8 || m == 10 || m == 12) return 31;
        if (m == 4 || m == 6 || m == 9 || m == 11) return 30;
        // February
        return isLeapYear(y) ? 29 : 28;
    }

    /// @notice Add `deltaYears` Gregorian years to a Unix timestamp (UTC).
    /// @dev Keeps month/day as much as possible; clamps Feb 29 -> Feb 28 when needed. Keeps time-of-day.
    function addYears(uint256 timestamp, uint16 deltaYears) internal pure returns (uint256) {
        // seconds -> days since epoch and seconds-of-day
        uint256 sod = timestamp % uint256(uint64(SECONDS_PER_DAY));
        int64 z = int64(int256(timestamp / uint256(uint64(SECONDS_PER_DAY))));
        (int64 y, uint8 mo, uint8 da) = _civilFromDays(z);

        if (y < 0) return timestamp; // defensive

        uint16 y2 = uint16(uint64(y)) + deltaYears;
        uint8 dim = daysInMonth(y2, mo);
        uint8 d2 = da <= dim ? da : dim;

        int64 days2 = _daysFromCivil(int64(uint64(y2)), mo, d2);
        if (days2 < 0) return timestamp; // defensive

        return uint256(uint64(days2)) * uint256(uint64(SECONDS_PER_DAY)) + sod;
    }

}
