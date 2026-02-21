// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IndBuckets1h.sol";

library IndBuckets1hSweep {
    using IndBuckets1h for IndBuckets1h.State;

    function removeLot(
        IndBuckets1h.State storage self,
        address owner,
        uint256 lotIndex
    ) internal {
        self._remove(owner, lotIndex);
    }
}
