# IND Canonical Upgradeable Vault Freeze

This freeze defines the canonical upgradeable IND vault baseline.

## Current architecture

The upgradeable vault is now bucket-native by design.

The protocol keeps:

- UUPS/ERC1967 upgradeability
- protected/unprotected balance split
- lot-level protected accounting
- 1h bucket indexing with linked bucket traversal
- revoke / reduceUnlockTime / sweep semantics
- IND key registry integration
- owner-to-signing-key recipient resolution
- protected-aware recipient gate
- invariant, stress, bucket-order and protected-receiver tests

## Protected receiver rule

Protected transfers to non-aware contracts are rejected.

Unprotected ERC20 transfers remain free and compatible with normal EOAs, CEXs, AMMs and generic contracts.

The protected gate applies only to protected/delayed transfers, not to normal ERC20 transfers.

## No separate V2 migration path

No separate V2 migration path exists anymore.

Sepolia should use a clean canonical deploy of the bucket-native upgradeable vault.

The former V1/V2 transition design and lazy migration layer are no longer part of the canonical freeze.
