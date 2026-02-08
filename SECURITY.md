# IND Protocol – Security Model

## 1. Security goals

The IND protocol is designed with the following primary security goals:

- Guarantee a mandatory waiting period before value transfer.
- Ensure the sender retains control during the waiting period.
- Prevent premature or forced execution of transfers.
- Minimize trust assumptions on recipients and intermediaries.

## 2. Key separation

The protocol enforces strict separation of cryptographic roles:

- **Signing keys** are used to authorize protocol actions.
- **Revocation keys** are used exclusively to revoke pending transfers.

Revocation keys MUST NOT be able to initiate transfers.
Signing keys MUST NOT be able to revoke transfers after the effective time.

## 3. Time enforcement

- Time constraints are enforced at protocol level.
- No implementation may bypass or shorten the minimum waiting period.
- Block timestamps or equivalent time sources MUST be used consistently.

## 4. Threat model

The protocol assumes that:

- Recipients may be malicious or uncooperative.
- Smart contracts interacting with IND may attempt to extract value early.
- Front-running and replay attempts are possible.

The protocol explicitly forbids any mechanism that allows
value availability before the effective time.

## 5. Non-goals

The protocol does NOT attempt to:

- Protect against key loss by the sender.
- Guarantee market liquidity.
- Prevent voluntary disclosure of private keys.

These concerns are outside the scope of IND.
