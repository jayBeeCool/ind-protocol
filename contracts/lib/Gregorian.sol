// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Gregorian helper for UTC year extraction.
/// @dev Robust version based on yearStartTs(), avoids edge-case bugs near epoch.
library Gregorian {
    function yearOf(uint256 ts) internal pure returns (uint16) {
        return yearFromTimestamp(ts);
    }

    function yearFromTimestamp(uint256 ts) internal pure returns (uint16) {
        // Lower-bound approximation from 1970 using 365-day years
        uint16 y = uint16(1970 + (ts / 365 days));

        // Fix upward while next year already started
        while (yearStartTs(uint16(y + 1)) <= ts) {
            unchecked {
                y++;
            }
        }

        // Fix downward if approximation overshot
        while (yearStartTs(y) > ts) {
            unchecked {
                y--;
            }
        }

        return y;
    }

    function isLeap(uint16 year) internal pure returns (bool) {
        uint256 y = uint256(year);
        if (y % 4 != 0) return false;
        if (y % 100 != 0) return true;
        return (y % 400 == 0);
    }

    function daysBeforeYear(uint16 year) internal pure returns (uint256) {
        uint256 y = uint256(year);
        require(y >= 1970, "year<1970");

        uint256 nYears = y - 1970;
        uint256 leaps = (uint256(year - 1) / 4 - uint256(1969) / 4) - (uint256(year - 1) / 100 - uint256(1969) / 100)
            + (uint256(year - 1) / 400 - uint256(1969) / 400);

        return nYears * 365 + leaps;
    }

    function yearStartTs(uint16 year) internal pure returns (uint256) {
        return daysBeforeYear(year) * 1 days;
    }

    function yearEndTs(uint16 year) internal pure returns (uint256) {
        unchecked {
            return yearStartTs(uint16(year + 1));
        }
    }
}
