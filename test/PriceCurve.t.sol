// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PriceCurve} from "../contracts/lib/PriceCurve.sol";

contract PriceCurveHarness {
    function priceAtSupply(uint256 supplyWei) external pure returns (uint256) {
        return PriceCurve.priceAtSupply(supplyWei);
    }

    function costToMint(uint256 currentSupplyWei, uint256 amountWei) external pure returns (uint256) {
        return PriceCurve.costToMint(currentSupplyWei, amountWei);
    }

    function quoteBuy(uint256 currentSupplyWei, uint256 ethInWei) external pure returns (uint256) {
        return PriceCurve.quoteBuy(currentSupplyWei, ethInWei);
    }
}

contract PriceCurveTest is Test {
    PriceCurveHarness internal h;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant MAX_SUPPLY = 100_000_000_000e18;

    function setUp() public {
        h = new PriceCurveHarness();
    }

    function test_priceAtSupply_zero_isZero() public view {
        uint256 p = h.priceAtSupply(0);
        assertEq(p, 0);
    }

    function test_priceAtSupply_10pct_matchesTarget() public view {
        uint256 supply10pct = 10_000_000_000e18; // 10%
        uint256 p = h.priceAtSupply(supply10pct);

        // target: 0.0000002 ETH = 2e11 wei
        assertApproxEqRel(p, 200_000_000_000, 1e14); // 0.01%
    }

    function test_costToMint_zeroAmount_isZero() public view {
        uint256 c = h.costToMint(0, 0);
        assertEq(c, 0);
    }

    function test_costToMint_positive() public view {
        uint256 c = h.costToMint(0, 1_000e18);
        assertGt(c, 0);
    }

    function test_quoteBuy_zeroEth_isZero() public view {
        uint256 q = h.quoteBuy(0, 0);
        assertEq(q, 0);
    }

    function test_quoteBuy_and_cost_roundtrip() public view {
        uint256 ethIn = 1 ether;
        uint256 amountOut = h.quoteBuy(0, ethIn);
        assertGt(amountOut, 0);

        uint256 cost = h.costToMint(0, amountOut);
        assertLe(cost, ethIn);

        if (amountOut + 1 <= MAX_SUPPLY - 1) {
            uint256 nextCost = h.costToMint(0, amountOut + 1);
            assertGt(nextCost, ethIn);
        }
    }

    function test_price_increases_with_supply() public view {
        uint256 p1 = h.priceAtSupply(1_000_000e18);
        uint256 p2 = h.priceAtSupply(10_000_000_000e18); // 10%
        uint256 p3 = h.priceAtSupply(50_000_000_000e18); // 50%

        assertLt(p1, p2);
        assertLt(p2, p3);
    }

    function test_revert_at_max_supply_price() public {
        vm.expectRevert(PriceCurve.SupplyAtOrAboveMax.selector);
        h.priceAtSupply(MAX_SUPPLY);
    }

    function test_revert_at_max_supply_cost() public {
        vm.expectRevert(PriceCurve.SupplyAtOrAboveMax.selector);
        h.costToMint(MAX_SUPPLY, 1e18);
    }

    function test_revert_if_end_reaches_max() public {
        vm.expectRevert(PriceCurve.EndSupplyAtOrAboveMax.selector);
        h.costToMint(MAX_SUPPLY - 1e18, 1e18);
    }
}
