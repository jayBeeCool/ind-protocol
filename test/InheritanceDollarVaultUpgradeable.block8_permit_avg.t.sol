// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InheritanceDollarVaultUpgradeable} from "../contracts/InheritanceDollarVaultUpgradeable.sol";
import {MockINDKeyRegistryLite} from "./mocks/MockINDKeyRegistryLite.sol";

contract InheritanceDollarVaultUpgradeableBlock8PermitAvgTest is Test {
    InheritanceDollarVaultUpgradeable internal ind;
    MockINDKeyRegistryLite internal reg;

    uint256 internal ownerPk = 0xA11CE55;
    address internal owner;
    address internal spender = address(0xBEEF);
    address internal admin = address(0xA11CE);
    address internal sale = address(0x5A1E);
    address internal bob = address(0xBBB2);

    uint256 internal constant MAX_SUPPLY = 100_000_000_000 ether;

    function setUp() external {
        owner = vm.addr(ownerPk);

        reg = new MockINDKeyRegistryLite();
        InheritanceDollarVaultUpgradeable impl = new InheritanceDollarVaultUpgradeable();

        bytes memory initData =
            abi.encodeCall(InheritanceDollarVaultUpgradeable.initialize, (admin, MAX_SUPPLY, address(reg)));

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        ind = InheritanceDollarVaultUpgradeable(address(proxy));

        vm.startPrank(admin);
        ind.grantRole(ind.MINTER_ROLE(), sale);
        vm.stopPrank();

        vm.prank(sale);
        ind.mint(owner, 100 ether);
    }

    function test_permit_sets_allowance_for_unprotected_only() external {
        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = ind.nonces(owner);

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                25 ether,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", ind.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 sSig) = vm.sign(ownerPk, digest);

        ind.permit(owner, spender, 25 ether, deadline, v, r, sSig);

        assertEq(ind.allowance(owner, spender), 25 ether);

        vm.prank(owner);
        ind.protect(80 ether);

        vm.prank(spender);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ind.transferFrom(owner, bob, 20 ether);

        assertEq(ind.unprotectedBalanceOf(bob), 20 ether);
        assertEq(ind.unprotectedBalanceOf(owner), 0);
        assertEq(ind.protectedBalanceOf(owner), 80 ether);
    }

    function test_average_balance_uses_unprotected_plus_protected_single_average() external {
        vm.warp(block.timestamp + 10 days);

        vm.prank(owner);
        ind.protect(40 ether);

        vm.warp(block.timestamp + 20 days);

        vm.prank(owner);
        ind.unprotect(10 ether);

        vm.warp(block.timestamp + 30 days);

        uint256 avg = ind.averageBalanceThisYear(owner);

        assertGt(avg, 99 ether);
        assertLt(avg, 101 ether);
    }

    function test_average_balance_changes_on_real_outgoing_change() external {
        vm.warp(block.timestamp + 10 days);

        vm.prank(owner);
        ind.protect(50 ether);

        vm.warp(block.timestamp + 10 days);

        vm.prank(owner);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ind.transfer(bob, 20 ether);

        vm.warp(block.timestamp + 10 days);

        uint256 avg = ind.averageBalanceThisYear(owner);

        assertLt(avg, 100 ether);
        assertGt(avg, 70 ether);
    }
}
