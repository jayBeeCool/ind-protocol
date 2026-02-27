# IND Protocol Specification (Draft)

## 1. Overview

IND is a protocol for deferred value transfer with a mandatory waiting period
and explicit revocation guarantees.

The protocol is intended to be compatible with existing smart contracts and markets,
while enforcing a minimum inheritance delay.

This document specifies protocol rules and security constraints. Implementations may
vary (ERC-20-like, escrow lots, account abstraction, etc.) as long as Sections 3 and 4
are satisfied.

## 2. Definitions

- **Sender**: the party initiating a transfer.
- **Recipient**: the party that will receive value after the waiting period.
- **Creation time**: the time at which a transfer is created.
- **Effective time**: the time at which a transfer becomes executable/claimable.
- **Minimum delay**: 86400 seconds (24 hours).
- All time values are expressed in **seconds**.

## 3. Time rules (normative)

- A transfer MUST define an effective time that is at least 86400 seconds in the future.
- After creation, the sender MAY reduce the effective time, but MUST NOT reduce it below
  86400 seconds from the current time.
- The effective time MUST NOT be increased after creation.

## 4. Revocation (normative)

- A transfer MAY be revoked by the sender before the effective time.
- Revocation authorization MUST use a key or authorization mechanism that is distinct
  from normal signing for transfer creation.
- After the effective time, revocation MUST be impossible.

## 5. Recipient constraints and enforcement model

### 5.1 Two possible enforcement models

If the implementation holds funds in escrow (or otherwise prevents early availability),
then the waiting period is enforced on-chain.

If the implementation exposes a freely transferable asset (e.g., a standard ERC-20),
then "recipient waiting period" is a protocol-level rule that may require integrator
compliance and cannot be universally enforced on-chain.

Implementations MUST state which model they implement.

### 5.2 This repository model (DECLARATION)

**This implementation uses an on-chain enforced escrow model based on per-recipient lots.**
Funds received are recorded into lots with an `unlockTime` and are not spendable before
unlock. This guarantees the minimum waiting period on-chain.

## 6. Key separation (normative extension)

To satisfy Section 4, implementations SHOULD provide distinct authorizers for:
- transfer creation / normal spending (e.g., **signing key**)
- revocation actions (e.g., **revoke key**)

If a registry is used to bind an "owner identity" to its keys, the implementation MUST
treat key roles distinctly for authorization checks.

## 7. Lots and spendability (implementation notes, consistent with Sections 3–4)

- Incoming value to a recipient is tracked as one or more **lots**.
- Each lot has at minimum: `amountRemaining`, `unlockTime` (and optionally `minUnlockTime`,
  `characteristic`, `lotIndex`).
- A transfer that creates a lot MUST set `unlockTime >= now + 86400`.
- A recipient MUST NOT be able to spend more than the sum of unlocked lot amounts.
  Attempting to spend locked value MUST revert.

## 8. Liveness and sweeping (implementation notes)

Some IND deployments may define a liveness rule for recipients and a corresponding
"sweep" operation (e.g., burn, refund to sender, or redirect to heir) when the recipient
is considered inactive/dead.

If a sweep operation exists:
- It MUST have a well-defined eligibility rule (e.g., “recipient is DEAD”).
- Sweeping an already-empty lot MUST revert with a deterministic error (e.g., `empty-lot`)
  rather than underflow/panic.

## 9. Scope

This specification defines protocol rules and security constraints.
Implementation details (ERC-20, EIP-712, EIP-4337, etc.) are allowed as long as
Sections 3 and 4 are satisfied.
