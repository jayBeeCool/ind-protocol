# IND Protocol — Audit Notes (dev)

This document is a pragmatic audit checklist + findings log.  
Goal: identify consensus-breaking bugs, fund-loss paths, vault bypasses, and DoS vectors.

## Scope
- contracts/InheritanceDollar.sol
- INDKeyRegistry (embedded)
- tests/ (unit + invariant)

## High-level invariants (must always hold)
1) ERC20: totalSupply() never exceeds MAX_SUPPLY
2) For any account a: balanceOf(a) == lockedBalanceOf(a) + spendableBalanceOf(a)
3) Spend requires spendable lots only (never spend locked)
4) Vault ON: outgoing transfers AND approvals only to IND signing keys
5) Receiving to initialized owner redirects to its signing key
6) Revoke key is never a receiver address in the intended wallet model

## Critical areas checklist

### A. Key registry correctness
- [ ] ownerOfSigningKey mapping updated on signing replace
- [ ] signingKey uniqueness (cannot be reused across owners)
- [ ] revokeKey uniqueness (cannot be reused across owners)
- [ ] rotateSigning: clears old mapping, sets new mapping
- [ ] rotateRevoke: does not accidentally allow receiving / misuse

### B. Owner/signing resolution & redirect
- [ ] senderOwner in lots is always the logical owner (even if sent by signingKey)
- [ ] _resolveRecipient(to): if to is initialized owner -> redirect to signingKey
- [ ] redirect never points to revokeKey

### C. Lots logic
- [ ] MIN_WAIT_SECONDS enforced
- [ ] MAX_WAIT_SECONDS enforced (anti-abuse)
- [ ] reduceUnlockTime: only reduction; >= minUnlockTime
- [ ] revoke: only before unlock; refunds to signingKey (or owner if not initialized)
- [ ] revoke does not create locked funds on refund target

### D. Spend accounting & head compaction
- [ ] _consumeSpendableLots consumes only unlockTime <= now
- [ ] head advances over zeros to prevent unbounded growth
- [ ] head never skips non-zero lots
- [ ] DoS: extreme lots count still bounded in gas? (best effort)

### E. Vault overlay (3.B + vault)
- [ ] vaultOn only by signingKey of initialized owner
- [ ] vaultOff only by revokeKey (immediate)
- [ ] Vault ON forbids transfer to non-IND signing keys
- [ ] Vault ON forbids approve/permit to non-IND signing keys
- [ ] transferFrom cannot bypass vault restrictions
- [ ] meta-tx paths also respect vault (because they call internal transfer path)
- [ ] Ensure no bypass via internal refunds/mint paths

### F. Liveness + default heir + burn
- [ ] lastSpendYear updated ONLY by spend actions (not receive)
- [ ] avg updates on both receive and send
- [ ] dead detection year calc correct boundaries
- [ ] both-dead => defaultHeir if alive else burn
- [ ] defaultHeir optional; can be changed
- [ ] defaultHeir cannot be revokeKey receiver by enforcement model

## Findings log (fill as we review)
- [ ] None yet
