# Sepolia pre-deploy checklist

## Build / test
- [ ] forge clean
- [ ] forge build
- [ ] forge test -vv
- [ ] 339/339 tests pass

## Manual semantic review
- [ ] `balanceOf != spendable` documented
- [ ] dead recipient semantics documented
- [ ] wallet shows free/protected balances separately

## Contract review
- [ ] `_logicalOwnerOf` reviewed
- [ ] `_primaryAccountOf` reviewed
- [ ] `_resolveRecipientRaw` reviewed
- [ ] `_activateKeysAndMigrate` reviewed
- [ ] `revokeReplaceSigningAndMigrate` reviewed
- [ ] `_autoSweepIfDead` reviewed
- [ ] `_inheritanceTarget` reviewed

## Roles
- [ ] admin chosen
- [ ] upgrader chosen
- [ ] minter chosen
- [ ] safe ownership/threshold confirmed

## Deploy discipline
- [ ] implementation address recorded
- [ ] proxy address recorded
- [ ] initializer args recorded
- [ ] post-deploy cast checks prepared

## Post-deploy checks
- [ ] name()
- [ ] symbol()
- [ ] decimals()
- [ ] maxSupply()
- [ ] registry()
- [ ] DEFAULT_ADMIN_ROLE assigned
- [ ] UPGRADER_ROLE assigned
- [ ] MINTER_ROLE assigned
