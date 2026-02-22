// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./Handler.t.sol";
import "../contracts/InheritanceDollar.sol";

contract Z_MirrorBuckets_Test is Test {
    INDHandler internal h;
    InheritanceDollar internal ind;

    function setUp() public {
        h = new INDHandler();
        ind = h.ind();
    }

    function test_mirror_totals_match_for_all_known_accounts() public {
        address[] memory owners = h.allOwners();
        address[] memory sks = h.allSigningKeys();

        for (uint256 i = 0; i < owners.length; i++) {
            address a = owners[i];
            uint256 lotsSpend = ind.spendableBalanceOf(a);
            uint256 lotsLock  = ind.lockedBalanceOf(a);
            uint256 buckSpend = ind.bucketsSpendableBalanceOf(a);
            uint256 buckLock  = ind.bucketsLockedBalanceOf(a);
            assertEq(lotsSpend, buckSpend, "mirror spendable mismatch (owner)");
            assertEq(lotsLock,  buckLock,  "mirror locked mismatch (owner)");
        }

        for (uint256 i = 0; i < sks.length; i++) {
            address a = sks[i];
            uint256 lotsSpend = ind.spendableBalanceOf(a);
            uint256 lotsLock  = ind.lockedBalanceOf(a);
            uint256 buckSpend = ind.bucketsSpendableBalanceOf(a);
            uint256 buckLock  = ind.bucketsLockedBalanceOf(a);
            assertEq(lotsSpend, buckSpend, "mirror spendable mismatch (sk)");
            assertEq(lotsLock,  buckLock,  "mirror locked mismatch (sk)");
        }
    }
}
