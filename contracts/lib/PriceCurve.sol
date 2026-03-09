// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/math/Math.sol";

library PriceCurve {
    uint256 internal constant WAD = 1e18;

    // 100,000,000,000 IND
    uint256 internal constant MAX_SUPPLY_WEI = 100_000_000_000e18;

    // k calibrato per avere circa:
    // P(10%) = 0.0000002 ETH per IND
    // k ≈ 0.0000106288 ETH
    uint256 internal constant K_WEI_PER_TOKEN = 10_628_800_000_000;

    error SupplyAtOrAboveMax();
    error EndSupplyAtOrAboveMax();

    /// Prezzo marginale a supply S:
    /// ritorna wei ETH per 1 IND.
    function priceAtSupply(uint256 supplyWei) internal pure returns (uint256) {
        if (supplyWei >= MAX_SUPPLY_WEI) revert SupplyAtOrAboveMax();

        uint256 uWad = Math.mulDiv(supplyWei, WAD, MAX_SUPPLY_WEI);

        // q = 1 / (1-u), in WAD
        uint256 denom = WAD - uWad;
        uint256 qWad = Math.mulDiv(WAD * WAD, 1, denom);

        uint256 q2 = Math.mulDiv(qWad, qWad, WAD);
        uint256 q4 = Math.mulDiv(q2, q2, WAD);
        uint256 q6 = Math.mulDiv(q4, q2, WAD);

        uint256 u2 = Math.mulDiv(uWad, uWad, WAD);

        // f(u) = u^2 / (1-u)^6 = u^2 * q^6
        uint256 fWad = Math.mulDiv(u2, q6, WAD);

        return Math.mulDiv(K_WEI_PER_TOKEN, fWad, WAD);
    }

    /// Costo totale approssimato con midpoint rule:
    /// cost ≈ price(currentSupply + amount/2) * amount
    ///
    /// ritorna wei ETH.
    function costToMint(uint256 currentSupplyWei, uint256 amountWei) internal pure returns (uint256) {
        if (currentSupplyWei >= MAX_SUPPLY_WEI) revert SupplyAtOrAboveMax();
        if (amountWei == 0) return 0;

        uint256 endSupplyWei = currentSupplyWei + amountWei;
        if (endSupplyWei >= MAX_SUPPLY_WEI) revert EndSupplyAtOrAboveMax();

        uint256 midSupplyWei = currentSupplyWei + amountWei / 2;
        uint256 priceWeiPerToken = priceAtSupply(midSupplyWei);

        // price is weiETH per 1 IND
        // amountWei is weiIND
        return Math.mulDiv(priceWeiPerToken, amountWei, WAD);
    }

    /// Quanti IND (wei-token) puoi comprare con `ethInWei`,
    /// partendo da `currentSupplyWei`.
    function quoteBuy(uint256 currentSupplyWei, uint256 ethInWei) internal pure returns (uint256) {
        if (currentSupplyWei >= MAX_SUPPLY_WEI) revert SupplyAtOrAboveMax();
        if (ethInWei == 0) return 0;

        uint256 remaining = (MAX_SUPPLY_WEI - 1) - currentSupplyWei;
        if (remaining == 0) return 0;

        uint256 lo = 0;
        uint256 hi = remaining;

        for (uint256 i = 0; i < 128; i++) {
            if (lo == hi) break;

            uint256 mid = (lo + hi + 1) >> 1;
            uint256 cost = costToMint(currentSupplyWei, mid);

            if (cost <= ethInWei) {
                lo = mid;
            } else {
                hi = mid - 1;
            }
        }

        return lo;
    }
}
