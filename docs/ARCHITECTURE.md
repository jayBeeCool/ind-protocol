# IND Architecture (dev)

## Goal
Max market compatibility (ERC20 + Permit) + maximum safety for reserves via Vault overlay.

## Actors / Keys
- Logical owner (Ethereum address used only for initial activation and identity)
- signingKey (hot): spends/transfers
- revokeKey (cold): reduce/revoke + vaultOff + key replacement

Wallet policy: revokeKey should not be used or stored online; it is loaded from cold storage only when needed.

## Core ERC20 behavior
- IND is ERC20 + ERC20Permit (EIP-2612).
- Transfers create "lots" on the recipient with unlock times.
- A lot becomes spendable only after unlockTime.
- Sender can reduce unlockTime (only reduce) or revoke entirely before unlock.

## Owner redirect
If someone transfers to an initialized owner address, the token redirects the recipient to the owner's signingKey.  
This prevents funds from being stuck on owner addresses and keeps the "active" balance on signing keys.

## Vault overlay (Reserve mode)
Vault is enabled per logical owner.

When Vault is ON for an owner:
- transfer/transferFrom: allowed only if recipient is an IND signing key
- approve/permit: allowed only if spender is an IND signing key

Vault ON:
- callable only by the owner's signingKey

Vault OFF:
- callable only by the owner's revokeKey (immediate)

This yields:
- Full ERC20 compatibility for onboarding/liquidity (base mode)
- A "closed network" for reserves when user enables Vault (IND-only transfers/approvals)

## Liveness / inactivity / burn
"Alive" is tracked only by spend actions (not receiving).
Inactivity threshold: INACTIVITY_YEARS.
When both parties are dead at unlock, defaultHeir is used if alive, otherwise burn.
