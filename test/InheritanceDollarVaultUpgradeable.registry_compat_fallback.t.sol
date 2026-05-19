// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InheritanceDollarVaultUpgradeable} from "../contracts/InheritanceDollarVaultUpgradeable.sol";

contract OldRegistryNoProtectedAware {
    mapping(address => bool) internal initialized;
    mapping(address => address) internal signing;
    mapping(address => address) internal ownerOfSigning;

    function setOwnerKeys(address owner, address signingKey) external {
        initialized[owner] = true;
        signing[owner] = signingKey;
        if (signingKey != address(0)) ownerOfSigning[signingKey] = owner;
    }

    function isInitialized(address owner) external view returns (bool) {
        return initialized[owner];
    }

    function ownerOfSigningKey(address signingKey) external view returns (address) {
        return ownerOfSigning[signingKey];
    }

    function signingKeyOf(address owner) external view returns (address) {
        return signing[owner];
    }

    function revokeKeyOf(address) external pure returns (address) {
        return address(0);
    }

    function initKeysFromAdmin(address owner, address signingKey, address) external {
        initialized[owner] = true;
        signing[owner] = signingKey;
        if (signingKey != address(0)) ownerOfSigning[signingKey] = owner;
    }

    function rotateSigningKeyFromRevoke(address owner, address newSigningKey) external {
        signing[owner] = newSigningKey;
        ownerOfSigning[newSigningKey] = owner;
    }
}

contract InheritanceDollarVaultUpgradeableRegistryCompatFallbackTest is Test {
    InheritanceDollarVaultUpgradeable internal ind;
    OldRegistryNoProtectedAware internal reg;

    address internal admin = address(0xA11CE);
    address internal sale = address(0x5A1E);
    address internal alice = address(0xAAA1);
    address internal bob = address(0xBBB2);
    address internal bobHot = address(0xB0B01);

    function setUp() external {
        reg = new OldRegistryNoProtectedAware();
        reg.setOwnerKeys(bob, bobHot);

        InheritanceDollarVaultUpgradeable impl = new InheritanceDollarVaultUpgradeable();
        bytes memory initData =
            abi.encodeCall(InheritanceDollarVaultUpgradeable.initialize, (admin, 1_000_000_000 ether, address(reg)));

        ind = InheritanceDollarVaultUpgradeable(address(new ERC1967Proxy(address(impl), initData)));

        vm.startPrank(admin);
        ind.grantRole(ind.MINTER_ROLE(), sale);
        vm.stopPrank();

        vm.prank(sale);
        ind.mint(alice, 100 ether);

        vm.prank(alice);
        ind.protect(100 ether);
    }

    function test_transferWithInheritance_works_with_old_registry_without_isProtectedAware() external {
        vm.prank(alice);
        assertTrue(ind.transferWithInheritance(bob, 50 ether, uint64(1 days), bytes32(0)));

        assertEq(ind.protectedBalanceOf(bobHot), 50 ether);
    }
}
