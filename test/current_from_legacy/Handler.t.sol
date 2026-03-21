// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {InheritanceDollar} from "../../contracts/InheritanceDollar.sol";
import {Test} from "forge-std/Test.sol";
import {INDKeyRegistry} from "../../contracts/InheritanceDollarCompat.sol";

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

    function _boundIdx(uint256 x, uint256 n) internal pure returns (uint256) {
        return n == 0 ? 0 : x % n;
    }

    function _spenderOf(uint256 ownerIdx) internal view returns (address) {
        address owner = owners[ownerIdx];
        if (reg.isInitialized(owner)) {
            address signingKey = reg.signingKeyOf(owner);
            if (signingKey != address(0)) {
                return signingKey;
            }
        }
        return owner;
    }

    function _revokeCallerOf(uint256 ownerIdx) internal view returns (address) {
        address owner = owners[ownerIdx];
        if (reg.isInitialized(owner)) {
            address revokeKey = reg.revokeKeyOf(owner);
            if (revokeKey != address(0)) {
                return revokeKey;
            }
        }
        return owner;
    }

    function actWarp(uint256 secs) external {
        uint256 delta = bound(secs, 0, 3 days);
        vm.warp(block.timestamp + delta);
    }

    function actActivate(uint256 ownerSeed) external {
        uint256 ownerIdx = _boundIdx(ownerSeed, owners.length);
        address owner = owners[ownerIdx];
        if (reg.isInitialized(owner)) {
            return;
        }

        vm.prank(owner);
        ind.activateKeysAndMigrate(signingKeys[ownerIdx], revokeKeys[ownerIdx]);
    }

    function actTransfer(uint256 fromSeed, uint256 toSeed, uint256 amtSeed) external {
        uint256 fromIdx = _boundIdx(fromSeed, owners.length);
        uint256 toIdx = _boundIdx(toSeed, owners.length);

        address from = _spenderOf(fromIdx);
        address to = owners[toIdx];
        if (from == to) {
            return;
        }

        uint256 spendable = ind.spendableBalanceOf(from);
        if (spendable == 0) {
            return;
        }

        uint256 amt = bound(amtSeed, 1, spendable);

        vm.prank(from);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        assertTrue(ind.transfer(to, amt));
    }

    function actTransferWithInheritance(uint256 fromSeed, uint256 toSeed, uint256 amtSeed, uint256 waitSeed) external {
        uint256 fromIdx = _boundIdx(fromSeed, owners.length);
        uint256 toIdx = _boundIdx(toSeed, owners.length);

        address from = _spenderOf(fromIdx);
        address to = owners[toIdx];
        if (from == to) {
            return;
        }

        uint256 spendable = ind.spendableBalanceOf(from);
        if (spendable == 0) {
            return;
        }

        uint256 amt = bound(amtSeed, 1, spendable);
        uint64 wait = uint64(bound(waitSeed, ind.MIN_WAIT_SECONDS(), ind.MIN_WAIT_SECONDS() + 3 days));

        vm.prank(from);
        ind.transferWithInheritance(to, amt, wait, bytes32(0));
    }

    function actReduce(uint256 ownerSeed, uint256 recipientSeed, uint256 lotSeed, uint256 newUnlockSeed) external {
        uint256 recipientIdx = _boundIdx(recipientSeed, owners.length);
        address recipient = owners[recipientIdx];

        InheritanceDollar.Lot[] memory lots = ind.getLots(recipient);
        if (lots.length == 0) {
            return;
        }

        uint256 lotIndex = _boundIdx(lotSeed, lots.length);
        InheritanceDollar.Lot memory lot = lots[lotIndex];
        if (lot.amount == 0 || block.timestamp >= lot.unlockTime) {
            return;
        }

        address ownerLogical = lot.senderOwner;
        if (ownerLogical == address(0)) {
            return;
        }

        uint256 ownerIdx = _boundIdx(ownerSeed, owners.length);
        if (owners[ownerIdx] != ownerLogical) {
            ownerIdx = type(uint256).max;
            for (uint256 k = 0; k < owners.length; k++) {
                if (owners[k] == ownerLogical) {
                    ownerIdx = k;
                    break;
                }
            }
        }
        if (ownerIdx == type(uint256).max) {
            return;
        }

        address caller = _revokeCallerOf(ownerIdx);

        uint64 minUnlock = lot.minUnlockTime;
        uint64 maxUnlock = lot.unlockTime - 1;
        if (maxUnlock < minUnlock) {
            return;
        }

        uint64 newUnlock = uint64(bound(newUnlockSeed, minUnlock, maxUnlock));

        vm.prank(caller);
        ind.reduceUnlockTime(recipient, lotIndex, newUnlock);
    }

    function actRevoke(
        uint256,
        /* ownerSeed */
        uint256 recipientSeed,
        uint256 lotSeed
    )
        external
    {
        uint256 recipientIdx = _boundIdx(recipientSeed, owners.length);
        address recipient = owners[recipientIdx];

        InheritanceDollar.Lot[] memory lots = ind.getLots(recipient);
        if (lots.length == 0) {
            return;
        }

        uint256 lotIndex = _boundIdx(lotSeed, lots.length);
        InheritanceDollar.Lot memory lot = lots[lotIndex];
        if (lot.amount == 0 || block.timestamp >= lot.unlockTime) {
            return;
        }

        address ownerLogical = lot.senderOwner;
        if (ownerLogical == address(0)) {
            return;
        }

        uint256 ownerIdx = type(uint256).max;
        for (uint256 k = 0; k < owners.length; k++) {
            if (owners[k] == ownerLogical) {
                ownerIdx = k;
                break;
            }
        }
        if (ownerIdx == type(uint256).max) {
            return;
        }

        address caller = _revokeCallerOf(ownerIdx);

        vm.prank(caller);
        ind.revoke(recipient, lotIndex);
    }

    function allOwners() external view returns (address[] memory) {
        return owners;
    }

    function allSigningKeys() external view returns (address[] memory) {
        return signingKeys;
    }
}
