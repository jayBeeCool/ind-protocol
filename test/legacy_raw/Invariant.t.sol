// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../contracts/InheritanceDollar.sol";

contract InvariantTest is Test {
    INDKeyRegistry reg;
    InheritanceDollar ind;

    address admin = address(0xA11CE);
    address alice = address(0xA);
    address bob = address(0xB);
    address carl = address(0xC);

    function setUp() public {
        vm.startPrank(admin);

        reg = new INDKeyRegistry(admin);
        ind = new InheritanceDollar(admin, reg);

        reg.grantRole(reg.REGISTRY_ADMIN_ROLE(), address(ind));

        ind.mint(alice, 1_000_000 ether);
        ind.mint(bob, 1_000_000 ether);

        vm.stopPrank();

        // only fuzz InheritanceDollar
        targetContract(address(ind));
    }

    function invariant_balance_split_correct() public {
        uint256 balA = ind.balanceOf(alice);
        uint256 lockedA = ind.lockedBalanceOf(alice);
        uint256 spendA = ind.spendableBalanceOf(alice);
        assertEq(balA, lockedA + spendA);

        uint256 balB = ind.balanceOf(bob);
        uint256 lockedB = ind.lockedBalanceOf(bob);
        uint256 spendB = ind.spendableBalanceOf(bob);
        assertEq(balB, lockedB + spendB);
    }

    function invariant_head_monotonic() public {
        uint256 headBefore = ind.headOf(bob);

        vm.warp(block.timestamp + 86400);

        // attempt safe spend only if possible
        uint256 spendable = ind.spendableBalanceOf(bob);
        bool initialized = reg.isInitialized(bob);
        if (spendable > 0 && !initialized) {
            vm.prank(bob);
            assertTrue(ind.transfer(carl, 1 ether));
        }

        uint256 headAfter = ind.headOf(bob);
        assertTrue(headAfter >= headBefore);
    }

    function invariant_total_supply_nonzero() public {
        assertTrue(ind.totalSupply() > 0);
    }
}
