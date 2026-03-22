# InheritanceDollarVaultUpgradeable — Surgical Audit

## Scope
- contracts/InheritanceDollarVaultUpgradeable.sol
- registry / signing / revoke interactions
- protected vs unprotected accounting
- inheritance / revoke / autosweep
- UUPS upgradeability
- ERC20 compatibility deviations

## Executive summary
No obvious critical exploit emerged from the current passing test suite. The main risks are structural and maintenance-related:
1. ERC20 semantic deviation by design
2. logical owner / signing key / revoke key indirection
3. inheritance sweep / autosweep transitions
4. upgradeable storage discipline

## Findings

### F-01 — `balanceOf` is not spendable balance
Severity: Medium
Status: Accepted by design

`balanceOf(account)` includes both unprotected and protected balances, while ordinary ERC20 spending only uses unprotected balance.

Impact:
- wallets / scripts may overestimate spendable amount
- UI must distinguish total / available / protected

Mitigation:
- wallet must display total, available, protected separately
- integrations should use `unprotectedBalanceOf` / `spendableBalanceOf`

### F-02 — ERC20 transfer semantics differ from standard expectations
Severity: Medium
Status: Accepted by design

`transfer` / `transferFrom` only spend unprotected balance. Protected balance cannot be spent through standard ERC20 flows.

Impact:
- generic ERC20 integrations may behave unexpectedly
- this is intended security behavior, not a bug

Mitigation:
- disable plain ERC20 send in wallet for IND
- route wallet flows through Vault-specific logic

### F-03 — Owner / signing / revoke indirection is a critical trust boundary
Severity: High
Status: Sensitive

Critical helpers:
- `_logicalOwnerOf`
- `_primaryAccountOf`
- `_resolveRecipientRaw`

Impact:
- future regressions here could silently redirect balances, liveness, revoke authority, or inheritance targets

Mitigation:
- preserve targeted tests
- review these helpers on every release
- avoid refactors without full regression testing

### F-04 — Migration flows are high-risk maintenance points
Severity: High
Status: Sensitive

Critical functions:
- `_activateKeysAndMigrate`
- `revokeReplaceSigningAndMigrate`

Impact:
- partial migration of balances / lots / head pointer could create accounting corruption

Mitigation:
- preserve migration tests
- treat migration logic as release-blocking review area

### F-05 — Autosweep / inheritance path is economically sensitive
Severity: High
Status: Sensitive

Critical functions:
- `sweepLot`
- `_autoSweepIfDead`
- `_inheritanceTarget`

Impact:
- burn vs heir-credit behavior depends on heir configuration and liveness
- this is intended, but highly sensitive economically

Mitigation:
- keep explicit tests for heir alive / dead / unset
- verify semantics before each deploy

### F-06 — Upgradeability / storage layout discipline
Severity: High
Status: Ongoing process risk

This is UUPS upgradeable storage.

Impact:
- reordering / retyping storage can break proxy state across upgrades

Mitigation:
- never reorder state vars
- preserve gap discipline
- run storage layout review before upgrades

### F-07 — Signature paths require replay discipline
Severity: Medium
Status: Acceptable with current tests

Critical functions:
- `permit`
- `transferWithInheritanceBySig`

Mitigation:
- keep nonce separation
- re-run signature tests on every release
- verify domain assumptions per deployed environment

## Conclusions
The contract is not “simple ERC20”; it is a semantic vault token with explicit protected/unprotected behavior.
The main risk is future maintenance drift, not an obvious present exploit.

Current conclusion:
- no obvious critical exploit found from current code + passing tests
- strongest discipline required around helper indirection, migration, autosweep, and upgradeability
