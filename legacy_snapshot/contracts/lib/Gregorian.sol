// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal Gregorian helper for UTC year extraction.
/// @dev Algorithm based on civil-from-days (proleptic Gregorian calendar).
library Gregorian {
    
    // IND compatibility: extension method used by token (uint256(ts).yearOf()).
    function yearOf(uint256 ts) internal pure returns (uint16) {
        return uint16(yearFromTimestamp(ts));
    }
/// @notice Returns the Gregorian year for a given unix timestamp (UTC).
    function yearFromTimestamp(uint256 ts) internal pure returns (uint16) {
        // Convert unix timestamp to days since 1970-01-01, then to "civil date".
        // 1970-01-01 corresponds to day 719468 in the civil-from-days algorithm.
        uint256 z = ts / 1 days + 719468;

        // era = floor(z / 146097) for z>=0 (z is uint so always >=0)
        uint256 era = z / 146097;
        uint256 doe = z - era * 146097; // [0, 146096]
        uint256 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365; // [0, 399]
        uint256 y = yoe + era * 400;

        // forge-lint: disable-next-line(unsafe-typecast)
        return uint16(y + 1);
    }

    /// @notice Returns true if `year` is a leap year in the proleptic Gregorian calendar.
    function isLeap(uint16 year) internal pure returns (bool) {
        uint256 y = uint256(year);
        if (y % 4 != 0) return false;
        if (y % 100 != 0) return true;
        return (y % 400 == 0);
    }

    /// @notice Days from 1970-01-01 to `year`-01-01 (UTC), proleptic Gregorian.
    function daysBeforeYear(uint16 year) internal pure returns (uint256) {
        // year >= 1970 assumed for on-chain time; still works for earlier but not needed.
        uint256 y = uint256(year);
        require(y >= 1970, "year<1970");
        uint256 y0 = y - 1;

        // Number of leap years up to y0 using Gregorian rules
        uint256 leaps = y0 / 4 - y0 / 100 + y0 / 400;
        uint256 leaps1969 = uint256(1969) / 4 - uint256(1969) / 100 + uint256(1969) / 400;

        // total days from year 0 to y-01-01 minus same for 1970-01-01
        // days to y-01-01 = 365*(y-1970) + (leaps up to y0 - leaps up to 1969)
        return 365 * (y - 1970) + (leaps - leaps1969);
    }

    /// @notice Unix timestamp (UTC) for 00:00:00 on Jan 1 of `year`.
    function yearStartTs(uint16 year) internal pure returns (uint256) {
        return daysBeforeYear(year) * 1 days;
    }

    /// @notice Unix timestamp (UTC) for 00:00:00 on Jan 1 of `year + 1` (exclusive end).
    function yearEndTs(uint16 year) internal pure returns (uint256) {
        unchecked {
            return yearStartTs(uint16(uint256(year) + 1));
        }
    }
}
