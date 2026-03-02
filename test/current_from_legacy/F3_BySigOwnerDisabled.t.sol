// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {InheritanceDollarTest} from "./InheritanceDollar.t.sol";

contract F3_BySigOwnerDisabled_Test is InheritanceDollarTest {
    function test_bySig_ownerDisabled_reverts() public {
        address owner = address(0xABCD01);
        address sk = address(0xABCD02);
        address rk = address(0xABCD03);

        vm.prank(owner);
        ind.activateKeysAndMigrateWithHeir(sk, rk, address(0));

        uint64 w = ind.MIN_WAIT_SECONDS();

        vm.expectRevert(bytes("owner-disabled"));

        ind.transferWithInheritanceBySig(
            owner, address(0xBEEF), 1 ether, w, bytes32(0), block.timestamp + 1 days, hex"00"
        );
    }
}
