// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "contracts/InheritanceDollarCompat.sol";

contract F2_RedirectOwnerReceive_Test is Test {
    INDKeyRegistry reg;
    InheritanceDollarCompat ind;

    address admin = address(0xD00D);

    uint256 ownerPk = 0xA11CE;
    uint256 signPk = 0xB0B;
    uint256 revokePk = 0xC01D;

    address owner;
    address signing;
    address revokeK;

    address bob = address(0xB);

    bytes32 constant TRANSFER_TYPEHASH = keccak256(
        "TransferInheritance(address from,address to,uint256 amount,uint64 waitSeconds,bytes32 characteristic,uint256 nonce,uint256 deadline)"
    );

    function setUp() public {
        owner = vm.addr(ownerPk);
        signing = vm.addr(signPk);
        revokeK = vm.addr(revokePk);

        reg = new INDKeyRegistry(admin);
        ind = new InheritanceDollarCompat(admin, reg);

        vm.startPrank(admin);
        reg.grantRole(reg.REGISTRY_ADMIN_ROLE(), address(ind));
        ind.mint(signing, 100 ether); // funds live on signing, not on owner
        vm.stopPrank();

        // activate keys for owner (owner becomes "logical owner" mapped to signing+revoke)
        vm.prank(owner);
        ind.activateKeysAndMigrate(signing, revokeK);
    }

    function test_transfer_to_owner_redirects_to_signing() public {
        // bob gets funds
        vm.prank(admin);
        ind.mint(bob, 10 ether);

        // bob sends to OWNER address, must end up at signing
        vm.prank(bob);
        assertTrue(ind.transfer(owner, 10 ether));

        assertEq(ind.balanceOf(owner), 0);
        assertEq(ind.balanceOf(signing), 110 ether); // 100 + 10
    }

    function _digest(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", ind.DOMAIN_SEPARATOR(), structHash));
    }

    function _sign(uint256 pk, bytes32 digest) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_bySig_to_owner_redirects_to_signing() public {
        // meta-tx from signing -> owner (should redirect to signing itself, effectively no-op recipient)
        uint256 nonce = reg.signingNonceOf(signing);
        uint256 deadline = block.timestamp + 1 days;

        bytes32 structHash = keccak256(
            abi.encode(TRANSFER_TYPEHASH, signing, owner, 1 ether, uint64(86400), bytes32(0), nonce, deadline)
        );

        bytes32 dig = _digest(structHash);
        bytes memory sig = _sign(signPk, dig);

        ind.transferWithInheritanceBySig(signing, owner, 1 ether, uint64(86400), bytes32(0), deadline, sig);

        // signing sent to owner but owner resolves to signing => net effect: balance unchanged
        assertEq(ind.balanceOf(owner), 0);
        assertEq(ind.balanceOf(signing), 100 ether); // stayed 100 (lot mechanics still exist)
    }
}
