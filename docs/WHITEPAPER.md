# Inheritance Dollar (IND)
## A deferred-transfer protocol with mandatory waiting and explicit revocation guarantees

**Version:** Draft (audit-freeze)  
**Repository:** ind-protocol  
**Status:** Specification frozen, audit-mode active.

---

## Abstract
Inheritance Dollar (IND) is a protocol for deferred value transfer with a mandatory minimum waiting period and explicit revocation guarantees. IND enforces the delay on-chain via per-recipient escrow “lots” with `unlockTime`, while maintaining compatibility with typical ERC-20 style transfers and integrations.

---

## 1. Motivation
Many transfers require a safety window to allow recovery from fraud, coercion, or mistakes. IND introduces a mandatory delay (minimum 24 hours) and a revocation model with key separation to make revocation explicit, reliable, and operationally safer.

---

## 2. Protocol Summary
IND defines:
- A transfer creates (or contributes to) a **lot** for the recipient.
- Each lot has an **unlockTime** and is **unspendable** until unlocked.
- The sender may **reduce** unlock time (never increase) within strict bounds.
- The sender may **revoke** prior to unlock, using a **distinct revoke authorization**.

---

## 3. Roles and Key Separation
IND separates authorization concerns:
- **signingKey (hot):** normal spending / transfer actions
- **revokeKey (cold):** revocation and time-reduction actions, key rotation

A key registry binds logical “owner identity” to these keys.

---

## 4. Time Rules (minimum wait)
- Time is expressed in seconds.
- Minimum delay is 86400 seconds (24 hours).
- Unlock time can be reduced only down to a minimum bound.

**Gregorian trigger policy (R25–R27):**
- If a reduction delta is **<= 365 days**, apply pure seconds arithmetic.
- If a reduction delta is **>= 365 days + 1 second**, apply calendar-year (gregorian) shifting + remainder seconds.

This rule prevents “flattening” every year to 365 days and preserves calendar correctness when long horizons are involved.

---

## 5. Lots and Spendability (escrow model)
This implementation uses an **on-chain enforced escrow model**:
- Incoming value is tracked as lots.
- Locked value cannot be spent early; attempts revert.
- Spendable balance is the sum of unlocked lot amounts.

---

## 6. Revocation
- Prior to unlock: sender may revoke using revoke authorization.
- After unlock: revocation is impossible (lot is effectively finalized by time).

---

## 7. Liveness and Sweeping (optional module)
IND may define “dead/inactive” detection for accounts and a permissionless **sweep**:
- eligibility is deterministic (e.g., inactivity threshold)
- sweep outcome is deterministic:
  - refund to sender, or redirect to heir, or burn as final fallback
- sweeping an already empty lot must revert deterministically (e.g., `empty-lot`)

---

## 8. Security Considerations
- Key separation reduces the blast radius of hot-key compromise.
- Nonce + deadline prevent signature replay.
- Deterministic sweep rules prevent ambiguity.
- Calendar-based policy avoids long-horizon drift.

---

## 9. Implementation Notes
Reference:
- `SPEC.md` (normative rules)
- `contracts/InheritanceDollar.sol`
- `contracts/lib/Gregorian.sol`
- `docs/AUDIT.md` (audit freeze checklist)

---

## 10. Disclaimer
This document is provided for technical discussion and audit purposes. It is not financial advice.
