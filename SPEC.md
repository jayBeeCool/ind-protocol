# IND Protocol Specification (Normative)

## 1. Overview

IND is a protocol for deferred value transfer with:
- a mandatory minimum waiting period (24h), and
- explicit revocation guarantees via a distinct authorization key.

The protocol is intended to be compatible with existing smart contracts and markets,
while enforcing a minimum inheritance delay.

This document specifies protocol rules and security constraints. Implementations may vary
(ERC-20-like, escrow lots, account abstraction, etc.) as long as the normative rules hold.

## 2. Definitions

- **Sender**: party initiating a transfer.
- **Recipient**: party that will receive value after the waiting period.
- **Creation time**: time a deferred transfer (lot) is created.
- **Effective time / unlockTime**: time at which recipient may spend the value.
- **minUnlockTime**: lower bound for unlockTime after creation.
- **Minimum delay**: 86400 seconds (24 hours).
- **All time values** are expressed in **seconds**.
- **Owner**: logical account identity.
- **signingKey (hot)**: authorizes transfers/spending.
- **revokeKey (cold)**: authorizes reduce/revoke, key rotation, critical controls.

## 3. Enforcement model (DECLARATION for this repository)

This repository implementation uses an **on-chain enforced escrow/lock model** based on
per-recipient lots: incoming value is recorded into lots with an `unlockTime` and is not
spendable before unlock. This guarantees the minimum waiting period on-chain.

## 4. Normative Rules (R1..R28)

### Time & Unlock

**R1 (Minimum delay).** Every deferred transfer MUST define `unlockTime >= now + 86400`.

**R2 (No early spend).** Before `unlockTime`, the recipient MUST NOT be able to spend the value.

**R3 (Reduction allowed, bounded).** Before `unlockTime`, the sender MAY reduce `unlockTime`,
but MUST NOT reduce it below `minUnlockTime`.

**R4 (No increase).** After creation, `unlockTime` MUST NOT be increased.

**R5 (After unlock, immutable).** After `unlockTime`, sender MUST NOT reduce or revoke.

### Revocation

**R6 (Revocation allowed only pre-unlock).** Before `unlockTime`, sender MAY revoke and recover value.

**R7 (Revocation impossible post-unlock).** After `unlockTime`, revocation MUST be impossible.

**R8 (Distinct authorization).** Revoke/reduce authorization MUST use a distinct key/mechanism
from normal transfer signing (operationally: `revokeKey`).

### Keys & Ownership

**R9 (Key separation).** Owner MUST have distinct `signingKey` and `revokeKey` (MUST NOT be equal).

**R10 (Uniqueness).** A signingKey/revokeKey MUST NOT be reused across owners.

**R11 (SigningKey scope).** signingKey authorizes transfers/spending only. It MUST NOT authorize
revoke/reduce/key-rotation.

**R12 (RevokeKey scope).** revokeKey authorizes revoke/reduce/default-heir updates/key rotations.

**R13 (Activation).** Owner MAY activate keys once. Activation MUST initialize registry bindings.

**R14 (Migration on activation).** On activation, any balance on owner MUST be migrated to signingKey
and made immediately spendable.

### Recipient handling & redirection

**R15 (Owner address non-trapping).** If tokens are sent/minted to an initialized owner address,
implementation MUST redirect to that owner’s signingKey.

**R16 (SigningKey receives normally).** If tokens are sent to a signingKey, they MUST land there.

### Lots & spendability

**R17 (Spendable vs total).** Implementation MUST define spendable balance distinct from total when locked.

**R18 (Consumption).** Only unlocked lots MUST be consumable; locked lots MUST remain locked.

### Liveness / Dead

**R19 (Liveness source).** Alive/Dead MUST be based only on signed outgoing actions.

**R20 (Never-seen non-strict).** Never-seen addresses MUST NOT be considered dead under non-strict checks.

**R21 (Strict mode).** Strict checks MAY treat never-seen as dead, only where explicitly intended.

### Sweep

**R22 (Sweep eligibility).** Sweep MUST only be allowed when recipient owner is dead per intended rule.

**R23 (Sweep priority).** Sweep MUST resolve in order:
1) refund to sender (or sender signingKey) if sender alive,
2) else default heir if configured and alive,
3) else burn.

**R24 (No double-sweep).** Sweeping an already-empty lot MUST revert deterministically (e.g. "empty-lot").

### Gregorian / Calendar policy (critical)

**R25 (Seconds vs calendar trigger).**
If a time delta is **<= 365 days**, it MUST be treated as pure seconds arithmetic.
If a time delta is **>= 365 days + 1 second**, it MUST be treated as calendar-based (Gregorian year shifting)
with remainder seconds.

**R26 (Calendar shift semantics).** Calendar shifting MUST preserve offset within UTC year when possible,
clamping safely if target year is shorter (leap/non-leap).

**R27 (No 365-flattening).** Implementations MUST NOT flatten years to 365 days when R25 triggers calendar mode.

### Scope

**R28 (Compatibility freedom).** Implementation details (ERC-20/EIP-712/EIP-4337/etc.) are allowed
as long as rules R1..R27 are satisfied.
