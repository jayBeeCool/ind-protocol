// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/math/Math.sol";

library PriceCurve {
    using Math for uint256;

    uint256 internal constant WAD = 1e18;

    // 100,000,000,000 IND
    uint256 internal constant MAX_SUPPLY_TOKENS = 100_000_000_000;
    uint256 internal constant MAX_SUPPLY_WEI = 100_000_000_000e18;

    // k = 0.000010632 ETH per 1 IND
    // in wei: 0.000010632 * 1e18 = 10_632_000_000_000
    uint256 internal constant K_WEI_PER_TOKEN = 10_632_000_000_000;

    error SupplyAtOrAboveMax();
    error EndSupplyAtOrAboveMax();
    error InvalidRange();

    /// Prezzo marginale a supply S:
    /// ritorna wei ETH per 1 IND.
    function priceAtSupply(uint256 supplyWei) internal pure returns (uint256) {
        if (supplyWei >= MAX_SUPPLY_WEI) revert SupplyAtOrAboveMax();

        uint256 uWad = _uWad(supplyWei);
        uint256 qWad = _qWad(uWad); // q = 1 / (1-u)
        uint256 q2 = _mulWad(qWad, qWad);
        uint256 q4 = _mulWad(q2, q2);
        uint256 q6 = _mulWad(q4, q2);

        uint256 u2 = _mulWad(uWad, uWad);

        // f(u) = u^2 * q^6
        uint256 fWad = _mulWad(u2, q6);

        // price = k * f(u)
        return Math.mulDiv(K_WEI_PER_TOKEN, fWad, WAD);
    }

    /// Costo totale in wei ETH per mintare `amountWei` IND
    /// partendo da `currentSupplyWei`.
    ///
    /// Usa la primitiva chiusa:
    /// ∫ u^2/(1-u)^6 du = 1/(5(1-u)^5) - 1/(2(1-u)^4) + 1/(3(1-u)^3) + C
    function costToMint(uint256 currentSupplyWei, uint256 amountWei) internal pure returns (uint256) {
        if (currentSupplyWei >= MAX_SUPPLY_WEI) revert SupplyAtOrAboveMax();
        if (amountWei == 0) return 0;

        uint256 endSupplyWei = currentSupplyWei + amountWei;
        if (endSupplyWei >= MAX_SUPPLY_WEI) revert EndSupplyAtOrAboveMax();

        uint256 f0 = _primitiveWad(currentSupplyWei);
        uint256 f1 = _primitiveWad(endSupplyWei);

        if (f1 < f0) revert InvalidRange();
        uint256 deltaFWad = f1 - f0;

        // Cost = k * M * deltaF
        // M = 100B tokens (non wei-token)
        return Math.mulDiv(K_WEI_PER_TOKEN * MAX_SUPPLY_TOKENS, deltaFWad, WAD);
    }

    /// Quanti IND (in wei-token) puoi comprare con `ethInWei`,
    /// partendo da `currentSupplyWei`.
    ///
    /// Implementazione: binary search sulla costToMint() chiusa.
    function quoteBuy(uint256 currentSupplyWei, uint256 ethInWei) internal pure returns (uint256) {
        if (currentSupplyWei >= MAX_SUPPLY_WEI) revert SupplyAtOrAboveMax();
        if (ethInWei == 0) return 0;

        uint256 remaining = MAX_SUPPLY_WEI - 1 - currentSupplyWei;
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

    function _uWad(uint256 supplyWei) private pure returns (uint256) {
        return Math.mulDiv(supplyWei, WAD, MAX_SUPPLY_WEI);
    }

    function _qWad(uint256 uWad) private pure returns (uint256) {
        uint256 denom = WAD - uWad;
        return Math.mulDiv(WAD * WAD, 1, denom);
    }

    function _mulWad(uint256 a, uint256 b) private pure returns (uint256) {
        return Math.mulDiv(a, b, WAD);
    }

    /// F(u) = 1/(5(1-u)^5) - 1/(2(1-u)^4) + 1/(3(1-u)^3) - 1/30
    /// con F(0)=0.
    function _primitiveWad(uint256 supplyWei) private pure returns (uint256) {
        uint256 uWad = _uWad(supplyWei);
        uint256 qWad = _qWad(uWad);

        uint256 q2 = _mulWad(qWad, qWad);
        uint256 q3 = _mulWad(q2, qWad);
        uint256 q4 = _mulWad(q2, q2);
        uint256 q5 = _mulWad(q4, qWad);

        uint256 term1 = q5 / 5;
        uint256 term2 = q4 / 2;
        uint256 term3 = q3 / 3;
        uint256 constantTerm = WAD / 30;

        return term1 - term2 + term3 - constantTerm;
    }
}
