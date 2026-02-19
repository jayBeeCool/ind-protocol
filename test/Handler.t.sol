// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/InheritanceDollar.sol";

contract INDHandler is Test {
    InheritanceDollar public ind;
    INDKeyRegistry public reg;

    address public admin;

    address[] public owners;
    address[] public signingKeys;
    address[] public revokeKeys;

    constructor(
        InheritanceDollar _ind,
        INDKeyRegistry _reg,
        address _admin,
        address[] memory _owners,
        address[] memory _signingKeys,
        address[] memory _revokeKeys
    ) {
        ind = _ind;
        reg = _reg;
        admin = _admin;

        owners = _owners;
        signingKeys = _signingKeys;
        revokeKeys = _revokeKeys;
    }

    // -------- helpers --------

    function _boundIdx(uint256 x, uint256 n) internal pure returns (uint256) {
        return n == 0 ? 0 : x % n;
    }

    function _spenderOf(uint256 ownerIdx) internal view returns (address) {
        address o = owners[ownerIdx];
        if (reg.isInitialized(o)) {
            address sk = reg.signingKeyOf(o);
            if (sk != address(0)) return sk;
        }
        return o;
    }

    function _revokeCallerOf(uint256 ownerIdx) internal view returns (address) {
        address o = owners[ownerIdx];
        if (reg.isInitialized(o)) {
            address rk = reg.revokeKeyOf(o);
            if (rk != address(0)) return rk;
        }
        return o;
    }

    // -------- actions (fuzzed) --------

    function act_warp(uint256 secs) external {
        uint256 delta = bound(secs, 0, 3 days);
        vm.warp(block.timestamp + delta);
    }

    function act_activate(uint256 ownerSeed) external {
        uint256 i = _boundIdx(ownerSeed, owners.length);
        address o = owners[i];
        if (reg.isInitialized(o)) return;

        vm.prank(o);
        ind.activateKeysAndMigrate(signingKeys[i], revokeKeys[i]);
    }

    function act_transfer(uint256 fromSeed, uint256 toSeed, uint256 amtSeed) external {
        uint256 i = _boundIdx(fromSeed, owners.length);
        uint256 j = _boundIdx(toSeed, owners.length);

        address from = _spenderOf(i);
        address to   = owners[j];
        if (from == to) return;

        uint256 spendable = ind.spendableBalanceOf(from);
        if (spendable == 0) return;

        uint256 amt = bound(amtSeed, 1, spendable);

        vm.prank(from);
        ind.transfer(to, amt);
    }

    function act_transferWithInheritance(
        uint256 fromSeed,
        uint256 toSeed,
        uint256 amtSeed,
        uint256 waitSeed
    ) external {
        uint256 i = _boundIdx(fromSeed, owners.length);
        uint256 j = _boundIdx(toSeed, owners.length);

        address from = _spenderOf(i);
        address to   = owners[j];
        if (from == to) return;

        uint256 spendable = ind.spendableBalanceOf(from);
        if (spendable == 0) return;

        uint256 amt = bound(amtSeed, 1, spendable);
        uint64 wait = uint64(bound(waitSeed, ind.MIN_WAIT_SECONDS(), ind.MIN_WAIT_SECONDS() + 3 days));

        vm.prank(from);
        ind.transferWithInheritance(to, amt, wait, bytes32(0));
    }

    function act_reduce(uint256 ownerSeed, uint256 recipientSeed, uint256 lotSeed, uint256 newUnlockSeed) external {
        uint256 oi = _boundIdx(ownerSeed, owners.length);
        uint256 ri = _boundIdx(recipientSeed, owners.length);

        address recipient = owners[ri];
        InheritanceDollar.Lot[] memory lots = ind.getLots(recipient);
        if (lots.length == 0) return;

        uint256 lotIndex = _boundIdx(lotSeed, lots.length);
        InheritanceDollar.Lot memory lot = lots[lotIndex];
        if (lot.amount == 0) return;
        if (block.timestamp >= lot.unlockTime) return;

        // Only the revoke controller of the *logical owner* can reduce
        address ownerLogical = lot.senderOwner;
        if (ownerLogical == address(0)) return;

        // Map ownerLogical -> its revoke caller by searching owners[]
        uint256 ownerIdx = type(uint256).max;
        for (uint256 k = 0; k < owners.length; k++) {
            if (owners[k] == ownerLogical) { ownerIdx = k; break; }
        }
        if (ownerIdx == type(uint256).max) return;

        address caller = _revokeCallerOf(ownerIdx);

        uint64 minU = lot.minUnlockTime;
        uint64 maxU = lot.unlockTime - 1;
        if (maxU < minU) return;

        uint64 newU = uint64(bound(newUnlockSeed, minU, maxU));

        vm.prank(caller);
        ind.reduceUnlockTime(recipient, lotIndex, newU);
    }

    function act_revoke(uint256 ownerSeed, uint256 recipientSeed, uint256 lotSeed) external {
        uint256 ri = _boundIdx(recipientSeed, owners.length);
        address recipient = owners[ri];

        InheritanceDollar.Lot[] memory lots = ind.getLots(recipient);
        if (lots.length == 0) return;

        uint256 lotIndex = _boundIdx(lotSeed, lots.length);
        InheritanceDollar.Lot memory lot = lots[lotIndex];
        if (lot.amount == 0) return;
        if (block.timestamp >= lot.unlockTime) return;

        address ownerLogical = lot.senderOwner;
        if (ownerLogical == address(0)) return;

        uint256 ownerIdx = type(uint256).max;
        for (uint256 k = 0; k < owners.length; k++) {
            if (owners[k] == ownerLogical) { ownerIdx = k; break; }
        }
        if (ownerIdx == type(uint256).max) return;

        address caller = _revokeCallerOf(ownerIdx);

        vm.prank(caller);
        ind.revoke(recipient, lotIndex);
    }

    // expose accounts to invariant test
    function allOwners() external view returns (address[] memory) { return owners; }
    function allSigningKeys() external view returns (address[] memory) { return signingKeys; }
}
