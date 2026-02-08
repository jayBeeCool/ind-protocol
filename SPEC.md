# IND Protocol Specification (Draft)

## 1. Overview

IND is a protocol for deferred value transfer with mandatory waiting periods
and explicit revocation guarantees.

The protocol is designed to be compatible with existing markets and smart contracts,
while enforcing a minimum inheritance delay.

## 2. Time rules

- All time values are expressed in seconds.
- A transfer effective time MUST be at least 86400 seconds (24 hours) in the future.
- Once set, the effective time MAY be reduced by the sender, but NEVER below 86400 seconds.
- The effective time MUST NOT be increased after creation.

## 3. Revocation

- A transfer MAY be revoked by the sender before the effective time.
- Revocation keys MUST be distinct from signing keys.
- After the effective time, revocation is no longer possible.

## 4. Recipients

- All recipients, including EOAs, smart contracts, DEXes, and custodial systems,
  MUST respect the waiting period.
- Immediate availability is not allowed under any circumstance.

## 5. Protocol scope

This specification defines logical and temporal rules only.
Implementation details (ERC-20, ERC-4337, EIP-712, etc.) are intentionally left open.
