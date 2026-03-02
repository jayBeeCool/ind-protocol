# AUDIT MODE (FREEZE)

Status: **AUDIT-FREEZE ACTIVE**
Branch policy:
- No new features.
- Only: bugfixes, tests, documentation, audit notes.
- Every change must include: rationale + risk + test proof.

## Scope
This audit covers the IND protocol implementation in this repository:
- `InheritanceDollar.sol` (core)
- `InheritanceDollarCompat.sol` (compat wrapper)
- `Gregorian.sol` (calendar support)
- test suites in `test/`

## Spec binding
The normative source is `SPEC.md` (R1..R28).
This audit focuses especially on:
- Time rules (R1..)
- Revocation key separation
- Liveness/dead detection and sweeping
- Gregorian trigger policy: **calendar-based when deltaSeconds >= 365d + 1s** (R25–R27)

## Critical invariants (must hold)
### Funds / accounting
- `balance == lockedBalance + spendableBalance` for any address.
- Spending cannot consume locked lots.
- Lot consumption must not skip partial lots.

### Time / unlock
- `unlockTime >= now + MIN_WAIT_SECONDS` at creation.
- `reduceUnlockTime`:
  - only reduces (never increases)
  - cannot reduce below `minUnlockTime`
  - policy: for reductions:
    - if deltaSeconds <= 365d => seconds arithmetic
    - if deltaSeconds >= 365d+1s => gregorian/calendar-based + remainder seconds

### Revocation / authorization
- revoke actions require revokeKey (cold key) when owner initialized.
- transfer/spend requires signingKey (hot key) when owner initialized.
- After unlock, revocation must be impossible (per lot rules).

### Liveness + sweeping
- DEAD eligibility is deterministic per spec/implementation.
- Sweeping an already empty lot must revert with deterministic error (`empty-lot`).
- Sweep outcome order is deterministic (refund/heir/burn paths).

## Attack surface checklist
- Reentrancy: ERC20 transfer hooks not used; still verify external calls.
- Signature replay: nonce handling, deadline checks, domain separator.
- Key registry: uniqueness constraints for signingKey and revokeKey.
- Edge cases: never-seen address, year boundaries, leap years.

## Evidence (tests)
- Gregorian vectors: `F01_*`
- Liveness/sweep: `F2_*`, `F3_*`
- Consumption edges/fuzz: `F4E_*`, `F4F_*`
- Invariants: `Invariant*.t.sol`

## Freeze tags
- `v1.1.1-audit-freeze` (main)
