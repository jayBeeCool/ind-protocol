# IND Threat Model (dev)

## Assets
- User funds (ERC20 balances represented as lots)
- Owner key mapping (logical owner -> signing/revoke)
- Vault state (owner -> on/off)
- Liveness state (lastSpendYear, avg state)

## Attacker models
1) Signing key theft
2) Revoke key theft (cold compromise)
3) Malicious dApp/DEX contract
4) User error: wrong address, wrong mode, mis-sent funds
5) Griefing: create many lots to cause gas blowups
6) Replay / signature misuse in meta-tx

## Key mitigations in this design
- Separation signing vs revoke
- Inheritance lock + revoke before unlock
- Vault ON to restrict interaction to IND-only network
- Vault OFF only by revoke key (immediate)
- Redirect owner->signing to prevent mis-sent owner funds getting stuck
- Spendability enforced by lots (no locked bypass)

## Residual risks / TODO
- Large-lots gas griefing (bounded by user behavior; consider batch sweeping or lot compaction strategy)
- Vault usability on exchanges (CEX deposit address may not be IND signing key)
- Meta-tx signer assumptions (signingKey vs owner)
