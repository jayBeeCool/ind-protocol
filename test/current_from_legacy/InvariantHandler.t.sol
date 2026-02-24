// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "contracts/InheritanceDollarCompat.sol";
import "./Handler.t.sol";

contract InvariantHandlerTest is StdInvariant, Test {
    INDKeyRegistry reg;
    InheritanceDollarCompat ind;
    INDHandler handler;

    address admin = address(0xA11CE);

    address alice = address(0xA);
    address bob = address(0xB);
    address carl = address(0xC);
    address dana = address(0xD);

    function setUp() public {
        vm.startPrank(admin);

        reg = new INDKeyRegistry(admin);
        ind = new InheritanceDollarCompat(admin, reg);
        reg.grantRole(reg.REGISTRY_ADMIN_ROLE(), address(ind));

        address[] memory owners = new address[](4);
        owners[0] = alice;
        owners[1] = bob;
        owners[2] = carl;
        owners[3] = dana;

        address[] memory signings = new address[](4);
        signings[0] = address(uint160(0x1111));
        signings[1] = address(uint160(0x2222));
        signings[2] = address(uint160(0x3333));
        signings[3] = address(uint160(0x4444));

        address[] memory revokes = new address[](4);
        revokes[0] = address(uint160(0xAAAA));
        revokes[1] = address(uint160(0xBBBB));
        revokes[2] = address(uint160(0xCCCC));
        revokes[3] = address(uint160(0xDDDD));

        handler = new INDHandler(ind, reg, admin, owners, signings, revokes);

        ind.mint(alice, 1_000_000 ether);
        ind.mint(bob, 1_000_000 ether);
        ind.mint(carl, 1_000_000 ether);
        ind.mint(dana, 1_000_000 ether);

        vm.stopPrank();

        targetContract(address(handler));
    }

    function invariant_balance_split_correct_for_all() public {
        address[] memory owners = handler.allOwners();
        address[] memory signings = handler.allSigningKeys();

        for (uint256 i = 0; i < owners.length; i++) {
            _checkAccount(owners[i]);
            _checkAccount(signings[i]);
        }
    }

    function _checkAccount(address a) internal {
        uint256 bal = ind.balanceOf(a);
        uint256 locked = ind.lockedBalanceOf(a);
        uint256 spend = ind.spendableBalanceOf(a);

        assertEq(bal, locked + spend);

        uint256 h = ind.headOf(a);
        InheritanceDollar.Lot[] memory lots = ind.getLots(a);
        assertTrue(h <= lots.length);

        uint256 start = h > 25 ? (h - 25) : 0;
        for (uint256 k = start; k < h; k++) {
            assertEq(lots[k].amount, 0);
        }
    }

    function invariant_total_supply_bounded() public {
        assertTrue(ind.totalSupply() <= ind.MAX_SUPPLY());
    }
}
