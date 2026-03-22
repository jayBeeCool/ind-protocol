# InheritanceDollarVaultUpgradeable — Surgical Audit

## Scope
- contracts/InheritanceDollarVaultUpgradeable.sol
- registry/signing/revoke interactions
- protected vs unprotected accounting
- inheritance / revoke / autosweep
- UUPS upgradeability
- ERC20 compatibility deviations

## Executive summary
No obvious critical exploit emerged from the current passing test suite, but the design has three structurally sensitive areas:
1. ERC20 semantic deviation
2. logical owner / signing key / revoke key indirection
3. inheritance sweep / autosweep state transitions

These require hardening through documentation, invariant locking, and pre-deploy discipline.

---

## Findings

### F-01 — ERC20 semantic deviation on dead recipient
**Severity:** medium  
**Status:** accepted-by-design, must be documented

`transfer` / `transferFrom` may return `true` while not crediting the nominal recipient when recipient logical owner is dead.

**Risk**
Integrators may assume `true` means recipient balance increased.

**Mitigation**
- document explicitly in wallet / deploy / integration notes
- keep dedicated tests for this semantic
- avoid presenting the token as ERC20-standard without caveat

---

### F-02 — `balanceOf` is not the spendable balance
**Severity:** medium  
**Status:** accepted-by-design, must be documented

`balanceOf = unprotected + protected`, while normal transfers only spend unprotected.

**Risk**
Wallets / scripts / UIs may overestimate spendable amount.

**Mitigation**
- wallet must show both balances
- integrations must use `unprotectedBalanceOf` / `spendableBalanceOf`

---

### F-03 — Logical owner resolution is a critical trust boundary
**Severity:** high  
**Status:** structurally sensitive

Critical helper functions:
- `_logicalOwnerOf`
- `_primaryAccountOf`
- `_resolveRecipientRaw`

**Risk**
Any future regression here can silently redirect balances, liveness, revoke authority, or inheritance target.

**Mitigation**
- freeze semantics with comments and targeted tests
- never refactor these helpers casually
- review these helpers on every release

---

### F-04 — Migration paths are high-risk maintenance points
**Severity:** high  
**Status:** structurally sensitive

Sensitive functions:
- `_activateKeysAndMigrate`
- `revokeReplaceSigningAndMigrate`

**Risk**
Partial migration of unprotected balances, protected lots, or `_head` may create invisible accounting corruption.

**Mitigation**
- preserve dedicated migration tests
- add release checklist item: migration path regression run mandatory

---

### F-05 — Autosweep / sweep semantics are economically sensitive
**Severity:** high  
**Status:** structurally sensitive

Sensitive functions:
- `sweepLot`
- `_autoSweepIfDead`
- `_inheritanceTarget`

**Risk**
Unexpected burn vs heir credit if default heir or heir liveness changes.

**Mitigation**
- require explicit operator/deployer checklist before Sepolia/Mainnet
- preserve tests around heir dead/alive and burn path

---

### F-06 — Upgradeability / storage layout discipline
**Severity:** high  
**Status:** ongoing process risk

This is UUPS upgradeable. Storage order is part of consensus for future upgrades.

**Risk**
Any reorder/type mutation breaks proxy storage.

**Mitigation**
- do not reorder storage vars
- do not rename/rework gap casually
- run storage diff before any upgrade
- maintain release notes for layout changes

---

### F-07 — Signature paths require replay discipline
**Severity:** medium  
**Status:** currently acceptable but sensitive

Sensitive functions:
- `permit`
- `transferWithInheritanceBySig`

**Mitigation**
- preserve nonce separation
- verify domain separator assumptions per deployment
- re-run signature tests on every release

---

## Pre-deploy hardening policy
1. `forge clean && forge build && forge test -vv`
2. storage layout review before upgrades
3. manual review of helper triad:
   - `_logicalOwnerOf`
   - `_primaryAccountOf`
   - `_resolveRecipientRaw`
4. manual review of migration functions
5. manual review of autosweep / heir / burn semantics
6. wallet UI must expose:
   - total
   - unprotected
   - protected
   - spendable
   - locked

## Conclusion
Current codebase appears test-clean, but the contract is semantically sophisticated. The greatest risk is future maintenance drift, not an obvious present exploit.
