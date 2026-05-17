# Sepolia Canonical Deploy Notes

Use the canonical upgradeable vault:

`contracts/InheritanceDollarVaultUpgradeable.sol`

Do not deploy `InheritanceDollarVaultUpgradeableV2.sol`.

The vault is already bucket-native and UUPS/ERC1967 upgradeable.

Deploy a fresh Sepolia stack. Do not upgrade the previous experimental proxy.

Expected properties:

- protected/unprotected split
- bucket-native protected lots
- protected receiver gate
- no separate V2 migration layer
- runtime below EIP-170
