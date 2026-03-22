# IND Wallet V2 Notes

## Mandatory wallet semantics
The wallet must not treat IND as a plain ERC20.

### Rules
1. Show:
   - total IND
   - available/unprotected IND
   - protected IND
   - ETH balance
2. Plain ERC20 `transfer(address,uint256)` must be disabled for IND in wallet flows.
3. Protected flows must use Vault-specific methods.
4. UI language must avoid implying that total IND is directly spendable.

## Reason
IND V2 uses a dual-balance model:
- unprotected = directly spendable by ERC20-style transfer
- protected = not spendable by standard ERC20 transfer/transferFrom
