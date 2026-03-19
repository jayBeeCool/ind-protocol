// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../contracts/InheritanceDollarVaultUpgradeable.sol";
import "./mocks/MockINDKeyRegistryLite.sol";

contract InheritanceDollarVaultUpgradeableBlock10CompatGapTest is Test {
    InheritanceDollarVaultUpgradeable ind;
    MockINDKeyRegistryLite reg;

    address admin = address(0xA11CE);
    address sale = address(0x5A1E);
    address owner = address(0xAAA1);
    address signing = address(0x1111);
    address revokeK = address(0x2222);
    address newSigning = address(0x3333);
    address bob = address(0xB0B);
    uint256 ownerPk = 0xAAA1;
    uint256 constant MAX_SUPPLY = 100_000_000_000 ether;

    function setUp() external {
        reg = new MockINDKeyRegistryLite();
        InheritanceDollarVaultUpgradeable impl = new InheritanceDollarVaultUpgradeable();
        bytes memory initData =
            abi.encodeCall(InheritanceDollarVaultUpgradeable.initialize, (admin, MAX_SUPPLY, address(reg)));
        ind = InheritanceDollarVaultUpgradeable(address(new ERC1967Proxy(address(impl), initData)));

        vm.startPrank(admin);
        ind.grantRole(ind.MINTER_ROLE(), sale);
        vm.stopPrank();
    }

    function test_activateKeysAndMigrate_moves_balance() external {
        vm.prank(sale);
        ind.mint(owner, 100 ether);

        vm.prank(owner);
        ind.activateKeysAndMigrate(signing, revokeK);

        assertEq(ind.balanceOf(owner), 0);
        assertEq(ind.balanceOf(signing), 100 ether);
    }

    function test_activateKeysAndMigrateWithHeir_sets_heir() external {
        vm.prank(sale);
        ind.mint(owner, 100 ether);

        vm.prank(owner);
        ind.activateKeysAndMigrateWithHeir(signing, revokeK, bob);

        assertEq(ind.defaultHeirOf(owner), bob);
    }

    function test_revokeReplaceSigningAndMigrate_moves_assets() external {
        vm.prank(sale);
        ind.mint(owner, 100 ether);

        vm.prank(owner);
        ind.activateKeysAndMigrate(signing, revokeK);

        vm.prank(signing);
        ind.protect(40 ether);

        vm.prank(revokeK);
        ind.revokeReplaceSigningAndMigrate(owner, newSigning);

        assertEq(ind.balanceOf(signing), 0);
        assertEq(ind.balanceOf(newSigning), 60 ether);
        assertEq(ind.protectedBalanceOf(newSigning), 40 ether);
    }

    function test_reduceUnlockTime_by_revoke_key() external {
        vm.prank(sale);
        ind.mint(owner, 100 ether);

        vm.prank(owner);
        ind.activateKeysAndMigrate(signing, revokeK);

        vm.prank(signing);
        ind.protect(50 ether);

        vm.prank(signing);
        ind.transferWithInheritance(bob, 10 ether, uint64(10 days), bytes32(0));

        InheritanceDollarVaultUpgradeable.Lot memory lot = ind.lotOf(bob, 0);
        uint64 newUnlock = lot.unlockTime - 1 days;

        vm.prank(revokeK);
        assertTrue(ind.reduceUnlockTime(bob, 0, newUnlock));

        lot = ind.lotOf(bob, 0);
        assertEq(lot.unlockTime, newUnlock);
    }

    function _buildTransferInheritanceDigest(
        address from,
        address to,
        uint256 amount,
        uint64 waitSeconds,
        bytes32 characteristic,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 typehash = keccak256(
            "TransferInheritance(address from,address to,uint256 amount,uint64 waitSeconds,bytes32 characteristic,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash =
            keccak256(abi.encode(typehash, from, to, amount, waitSeconds, characteristic, nonce, deadline));

        return keccak256(abi.encodePacked("\x19\x01", ind.DOMAIN_SEPARATOR(), structHash));
    }

    function _callTransferWithInheritanceBySig(
        address from,
        address to,
        uint256 amount,
        uint64 waitSeconds,
        bytes32 characteristic,
        uint256 deadline,
        bytes memory sig
    ) internal {
        ind.transferWithInheritanceBySig(from, to, amount, waitSeconds, characteristic, deadline, sig);
    }

    function test_transferWithInheritanceBySig() external {
        owner = vm.addr(ownerPk);

        vm.prank(sale);
        ind.mint(owner, 100 ether);

        vm.prank(owner);
        ind.protect(100 ether);

        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = ind.transferWithInheritanceNonces(owner);
        uint64 waitSeconds = uint64(3 days);
        bytes32 characteristic = bytes32(uint256(7));

        bytes32 digest =
            _buildTransferInheritanceDigest(owner, bob, 25 ether, waitSeconds, characteristic, nonce, deadline);

        (uint8 v, bytes32 r, bytes32 sSig) = vm.sign(ownerPk, digest);
        bytes memory sig = abi.encodePacked(r, sSig, v);

        _callTransferWithInheritanceBySig(owner, bob, 25 ether, waitSeconds, characteristic, deadline, sig);

        assertEq(ind.protectedBalanceOf(bob), 25 ether);
    }
}
