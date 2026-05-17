// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InheritanceDollarVaultUpgradeable} from "../contracts/InheritanceDollarVaultUpgradeable.sol";
import {MockINDKeyRegistryLite} from "./mocks/MockINDKeyRegistryLite.sol";

contract GenericNonAwareContract {
    // intentionally empty

    }

contract Create2StyleAddressFactory {
    function compute(bytes32 salt) external view returns (address predicted) {
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(type(GenericNonAwareContract).creationCode))
        );
        predicted = address(uint160(uint256(hash)));
    }
}

contract InheritanceDollarVaultUpgradeableProtectedReceiverGateTest is Test {
    InheritanceDollarVaultUpgradeable internal ind;
    MockINDKeyRegistryLite internal reg;
    GenericNonAwareContract internal generic;
    Create2StyleAddressFactory internal factory;

    address internal admin = address(0xA11CE);
    address internal sale = address(0x5A1E);
    address internal alice = address(0xAAA1);
    address internal bobOwner = address(0xBBB2);
    address internal bobSigning = address(0xB0B51);
    address internal contractSigning = address(0x5151);

    uint256 internal constant MAX_SUPPLY = 100_000_000_000 ether;

    function setUp() external {
        reg = new MockINDKeyRegistryLite();
        generic = new GenericNonAwareContract();
        factory = new Create2StyleAddressFactory();

        InheritanceDollarVaultUpgradeable impl = new InheritanceDollarVaultUpgradeable();
        bytes memory initData =
            abi.encodeCall(InheritanceDollarVaultUpgradeable.initialize, (admin, MAX_SUPPLY, address(reg)));

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        ind = InheritanceDollarVaultUpgradeable(address(proxy));

        bytes32 minterRole = ind.MINTER_ROLE();

        vm.prank(admin);
        ind.grantRole(minterRole, sale);

        vm.prank(sale);
        ind.mint(alice, 100 ether);
    }

    function test_unprotected_transfer_to_generic_contract_remains_allowed() external {
        vm.prank(alice);
        assertTrue(ind.transfer(address(generic), 10 ether));

        assertEq(ind.unprotectedBalanceOf(address(generic)), 10 ether);
    }

    function test_protected_transfer_to_unregistered_eoa_reverts() external {
        vm.prank(alice);
        assertTrue(ind.protect(10 ether));

        vm.prank(alice);
        vm.expectRevert(InheritanceDollarVaultUpgradeable.RecipientNotProtectedAware.selector);
        ind.transferWithInheritance(bobOwner, 1 ether, uint64(1 days), bytes32(0));
    }

    function test_protected_transfer_to_generic_contract_reverts() external {
        vm.prank(alice);
        assertTrue(ind.protect(10 ether));

        vm.prank(alice);
        vm.expectRevert(InheritanceDollarVaultUpgradeable.RecipientNotProtectedAware.selector);
        ind.transferWithInheritance(address(generic), 1 ether, uint64(1 days), bytes32(0));
    }

    function test_protected_transfer_to_registered_owner_redirects_to_signing_key() external {
        reg.setOwnerKeys(bobOwner, bobSigning);

        vm.prank(alice);
        assertTrue(ind.protect(10 ether));

        vm.prank(alice);
        assertTrue(ind.transferWithInheritance(bobOwner, 1 ether, uint64(1 days), bytes32(0)));

        assertEq(ind.protectedBalanceOf(bobOwner), 0);
        assertEq(ind.protectedBalanceOf(bobSigning), 1 ether);
    }

    function test_protected_transfer_to_registered_contract_owner_redirects_to_signing_key() external {
        reg.setOwnerKeys(address(generic), contractSigning);

        vm.prank(alice);
        assertTrue(ind.protect(10 ether));

        vm.prank(alice);
        assertTrue(ind.transferWithInheritance(address(generic), 1 ether, uint64(1 days), bytes32(0)));

        assertEq(ind.protectedBalanceOf(address(generic)), 0);
        assertEq(ind.protectedBalanceOf(contractSigning), 1 ether);
    }

    function test_protected_transfer_to_create2_style_uninitialized_address_reverts() external {
        address predicted = factory.compute(keccak256("IND_CREATE2_TEST"));

        vm.prank(alice);
        assertTrue(ind.protect(10 ether));

        vm.prank(alice);
        vm.expectRevert(InheritanceDollarVaultUpgradeable.RecipientNotProtectedAware.selector);
        ind.transferWithInheritance(predicted, 1 ether, uint64(1 days), bytes32(0));
    }
}
