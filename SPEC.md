# IND Protocol Specification (Draft)

## 1. Overview

IND is a protocol for deferred value transfer with a mandatory waiting period
and explicit revocation guarantees.

The protocol is intended to be compatible with existing smart contracts and markets,
while enforcing a minimum inheritance delay.

## 2. Definitions

- **Sender**: the party initiating a transfer.
- **Recipient**: the party that will receive value after the waiting period.
- **Creation time**: the time at which a transfer is created.
- **Effective time**: the time at which a transfer becomes executable/claimable.
- **Minimum delay**: 86400 seconds (24 hours).
- All time values are expressed in **seconds**.

## 3. Time rules (normative)

- A transfer MUST define an effective time that is at least 86400 seconds in the future.
- After creation, the sender MAY reduce the effective time, but MUST NOT reduce it below 86400 seconds from the current time.
- The effective time MUST NOT be increased after creation.

## 4. Revocation (normative)

- A transfer MAY be revoked by the sender before the effective time.
- Revocation authorization MUST use a key or authorization mechanism that is distinct from normal signing for transfer creation.
- After the effective time, revocation MUST be impossible.

## 5. Recipient constraints

If the implementation holds funds in escrow (or otherwise prevents early availability),
then the waiting period is enforced on-chain.

If the implementation exposes a freely transferable asset (e.g., a standard ERC-20),
then "recipient waiting period" is a protocol-level rule that may require
integrator compliance and cannot be universally enforced on-chain.

Implementations MUST state which model they implement.

## 6. Scope

This specification defines protocol rules and security constraints.
Implementation details (ERC-20, EIP-712, EIP-4337, etc.) are allowed as long as
Sections 3 and 4 are satisfied.
