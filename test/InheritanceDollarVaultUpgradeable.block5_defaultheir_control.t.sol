// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../contracts/InheritanceDollarVaultUpgradeable.sol";
import "./mocks/MockINDKeyRegistryLite.sol";

contract InheritanceDollarVaultUpgradeableBlock5DefaultHeirControlTest is Test {
    InheritanceDollarVaultUpgradeable internal ind;
    MockINDKeyRegistryLite internal reg;

    address internal admin = address(0xA11CE);
    address internal sale = address(0x5A1E);
    address internal owner = address(0xAAA1);
    address internal signing = address(0x1111);
    address internal revokeK = address(0x2222);
    address internal heir1 = address(0x3333);
    address internal heir2 = address(0x4444);

    uint256 internal constant MAX_SUPPLY = 100_000_000_000 ether;

    function setUp() external {
        reg = new MockINDKeyRegistryLite();
        InheritanceDollarVaultUpgradeable impl = new InheritanceDollarVaultUpgradeable();

        bytes memory initData =
            abi.encodeCall(InheritanceDollarVaultUpgradeable.initialize, (admin, MAX_SUPPLY, address(reg)));

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        ind = InheritanceDollarVaultUpgradeable(address(proxy));

        vm.startPrank(admin);
        ind.grantRole(ind.MINTER_ROLE(), sale);
        vm.stopPrank();
    }

    function test_uninitialized_owner_can_set_default_heir() external {
        vm.prank(owner);
        assertTrue(ind.setDefaultHeir(heir1));

        assertEq(ind.defaultHeirOf(owner), heir1);
    }

    function test_initialized_owner_cannot_set_default_heir() external {
        reg.setOwnerKeys(owner, signing, revokeK);

        vm.prank(owner);
        vm.expectRevert(bytes4(0xf28dceb3));
        ind.setDefaultHeir(heir1);
    }

    function test_signing_key_cannot_set_default_heir() external {
        reg.setOwnerKeys(owner, signing, revokeK);

        vm.prank(signing);
        vm.expectRevert(bytes4(0xf28dceb3));
        ind.setDefaultHeir(heir1);
    }

    function test_only_revoke_key_can_change_default_heir_after_initialization() external {
        vm.prank(owner);
        ind.setDefaultHeir(heir1);

        reg.setOwnerKeys(owner, signing, revokeK);

        vm.prank(revokeK);
        assertTrue(ind.revokeSetDefaultHeir(owner, heir2));

        assertEq(ind.defaultHeirOf(owner), heir2);
    }

    function test_non_revoke_key_cannot_change_default_heir() external {
        reg.setOwnerKeys(owner, signing, revokeK);

        vm.prank(owner);
        vm.expectRevert(InheritanceDollarVaultUpgradeable.NotRevoke.selector);
        ind.revokeSetDefaultHeir(owner, heir2);
    }
}
