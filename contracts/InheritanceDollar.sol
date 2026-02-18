// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/*
Inheritance Dollar (IND)

RULES (FINAL):
- All time values are expressed in SECONDS. 24h = 86400.
- The sender chooses when the recipient will be able to spend the tokens (waitSeconds >= 86400).
- For each transfer, a "lot" is created on the recipient.
- Until unlockTime is reached, the original sender may:
  1) reduce the unlockTime (only reduce, never increase),
     but never below createdAt + 86400
  2) revoke the transfer entirely, recovering the funds
- Two separate keys per owner:
  - signingKey (hot): authorizes transfers
  - revokeKey (cold): authorizes reduce/revoke and key rotation
- ERC20 standard compatibility + Permit (EIP-2612)
- Meta-transactions via EIP-712 for maximum market compatibility
*/

/// ------------------------------------------------------------------------
/// Key Registry
/// ------------------------------------------------------------------------
contract INDKeyRegistry is AccessControl {
    bytes32 public constant REGISTRY_ADMIN_ROLE = keccak256("REGISTRY_ADMIN_ROLE");

    struct Keys {
        address signingKey;   // hot key (transfers)
        address revokeKey;    // cold key (reduce/revoke)
        uint256 signingNonce;
        uint256 revokeNonce;
        bool initialized;
    }

    mapping(address => Keys) private _keys;
    mapping(address => address) private _ownerOfSigning;

    event KeysInitialized(address indexed owner, address indexed signingKey, address indexed revokeKey);
    event SigningKeyRotated(address indexed owner, address indexed oldKey, address indexed newKey, uint256 revokeNonce);
    event RevokeKeyRotated(address indexed owner, address indexed oldKey, address indexed newKey, uint256 revokeNonce);
    event SigningNonceUsed(address indexed owner, uint256 nonce);
    event RevokeNonceUsed(address indexed owner, uint256 nonce);

    constructor(address admin) {
        require(admin != address(0), "admin=0");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRY_ADMIN_ROLE, admin);
    }

    // -------- Views --------

    function signingKeyOf(address owner) external view returns (address) {
        Keys storage k = _keys[owner];
        return k.initialized ? k.signingKey : address(0);
    }

    function revokeKeyOf(address owner) external view returns (address) {
        Keys storage k = _keys[owner];
        return k.initialized ? k.revokeKey : address(0);
    }

    function signingNonceOf(address owner) external view returns (uint256) {
        return _keys[owner].signingNonce;
    }

    function revokeNonceOf(address owner) external view returns (uint256) {
        return _keys[owner].revokeNonce;
    }

    function isInitialized(address owner) external view returns (bool) {
        return _keys[owner].initialized;
    }

    function ownerOfSigningKey(address signingKey) external view returns (address) {
        return _ownerOfSigning[signingKey];
    }


    // -------- Initialization --------

    function initKeys(address signingKey, address revokeKey) external {
        require(signingKey != address(0), "signingKey=0");
        require(revokeKey != address(0), "revokeKey=0");

        Keys storage k = _keys[msg.sender];
        require(!k.initialized, "already-initialized");

        k.signingKey = signingKey;
        k.revokeKey  = revokeKey;
        k.signingNonce = 0;
        k.revokeNonce  = 0;
        k.initialized  = true;

        _ownerOfSigning[signingKey] = msg.sender;

        emit KeysInitialized(msg.sender, signingKey, revokeKey);
    }


    // -------- Rotations (B1+B) --------

    function rotateSigning(address owner, address newSigning) external {
        require(newSigning != address(0), "signingKey=0");
        Keys storage k = _keys[owner];
        require(k.initialized, "not-initialized");
        require(msg.sender == k.revokeKey, "not-revoke");
        address old = k.signingKey;

        delete _ownerOfSigning[old];
        _ownerOfSigning[newSigning] = owner;
        k.signingKey = newSigning;
        k.revokeNonce++;
        emit SigningKeyRotated(owner, old, newSigning, k.revokeNonce - 1);
    }

    function rotateRevoke(address owner, address newRevoke) external {
        require(newRevoke != address(0), "revokeKey=0");
        Keys storage k = _keys[owner];
        require(k.initialized, "not-initialized");
        require(msg.sender == k.revokeKey, "not-revoke");
        address old = k.revokeKey;
        k.revokeKey = newRevoke;
        k.revokeNonce++;
        emit RevokeKeyRotated(owner, old, newRevoke, k.revokeNonce - 1);
    }


    function initKeysFromAdmin(address owner, address signingKey, address revokeKey)
        external
        onlyRole(REGISTRY_ADMIN_ROLE)
    {
        require(owner != address(0), "owner=0");
        require(signingKey != address(0), "signingKey=0");
        require(revokeKey != address(0), "revokeKey=0");

        Keys storage k = _keys[owner];
        require(!k.initialized, "already-initialized");

        k.signingKey = signingKey;
        k.revokeKey  = revokeKey;
        k.signingNonce = 0;
        k.revokeNonce  = 0;
        k.initialized  = true;
        _ownerOfSigning[signingKey] = owner;


        emit KeysInitialized(owner, signingKey, revokeKey);
    }

    // -------- Admin helpers (called by token after signature verification) --------

    function useSigningNonce(address owner, uint256 expected)
        external
        onlyRole(REGISTRY_ADMIN_ROLE)
    {
        Keys storage k = _keys[owner];
        require(k.signingNonce == expected, "bad-signing-nonce");
        k.signingNonce++;
        emit SigningNonceUsed(owner, expected);
    }

    function useRevokeNonce(address owner, uint256 expected)
        external
        onlyRole(REGISTRY_ADMIN_ROLE)
    {
        Keys storage k = _keys[owner];
        require(k.revokeNonce == expected, "bad-revoke-nonce");
        k.revokeNonce++;
        emit RevokeNonceUsed(owner, expected);
    }

    function setSigningKeyFromAdmin(address owner, address newKey)
        external
        onlyRole(REGISTRY_ADMIN_ROLE)
    {
        Keys storage k = _keys[owner];
        require(k.initialized, "not-initialized");
        address old = k.signingKey;
        k.signingKey = newKey;
        emit SigningKeyRotated(owner, old, newKey, k.revokeNonce);
    }

    function setRevokeKeyFromAdmin(address owner, address newKey)
        external
        onlyRole(REGISTRY_ADMIN_ROLE)
    {
        Keys storage k = _keys[owner];
        require(k.initialized, "not-initialized");
        address old = k.revokeKey;
        k.revokeKey = newKey;
        emit RevokeKeyRotated(owner, old, newKey, k.revokeNonce);
    }
}

/// ------------------------------------------------------------------------
/// Inheritance Dollar Token
/// ------------------------------------------------------------------------
contract InheritanceDollar is ERC20Permit, AccessControl {
    using ECDSA for bytes32;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint64 public constant MIN_WAIT_SECONDS = 86400; // 24 hours

    INDKeyRegistry public immutable registry;

    struct Lot {
        address senderOwner;      // original sender (controls reduce/revoke)
        uint128 amount;
        uint64  createdAt;
        uint64  minUnlockTime;    // createdAt + 86400
        uint64  unlockTime;
        bytes32 characteristic;
    }

    mapping(address => Lot[]) private _lots;

    // -------- EIP-712 typehashes --------
    bytes32 private constant TRANSFER_TYPEHASH =
        keccak256(
            "TransferInheritance(address from,address to,uint256 amount,uint64 waitSeconds,bytes32 characteristic,uint256 nonce,uint256 deadline)"
        );

    bytes32 private constant REDUCE_TYPEHASH =
        keccak256(
            "ReduceUnlockTime(address sender,address recipient,uint256 lotIndex,uint64 newUnlockTime,uint256 nonce,uint256 deadline)"
        );

    bytes32 private constant REVOKE_TYPEHASH =
        keccak256(
            "RevokeLot(address sender,address recipient,uint256 lotIndex,uint256 nonce,uint256 deadline)"
        );

    // -------- Events --------
    event TransferWithInheritance(
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        uint64 unlockTime,
        uint64 minUnlockTime,
        bytes32 indexed characteristic,
        uint256 lotIndex
    );

    event UnlockTimeReduced(
        address indexed sender,
        address indexed recipient,
        uint256 indexed lotIndex,
        uint64 oldUnlockTime,
        uint64 newUnlockTime
    );

    event Revoked(
        address indexed sender,
        address indexed recipient,
        uint256 indexed lotIndex,
        uint256 amount
    );

    constructor(address admin, INDKeyRegistry keyRegistry)
        ERC20("Inheritance Dollar", "IND")
        ERC20Permit("Inheritance Dollar")
    {
        require(admin != address(0), "admin=0");
        require(address(keyRegistry) != address(0), "registry=0");

        registry = keyRegistry;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    // --------------------------------------------------------------------
    // Views
    // --------------------------------------------------------------------

    function getLots(address account) external view returns (Lot[] memory) {
        return _lots[account];
    }

    function spendableBalanceOf(address account) public view returns (uint256) {
        Lot[] storage arr = _lots[account];
        uint256 sum;
        uint64 nowTs = uint64(block.timestamp);

        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i].amount != 0 && arr[i].unlockTime <= nowTs) {
                sum += uint256(arr[i].amount);
            }
        }
        return sum;
    }

    function lockedBalanceOf(address account) public view returns (uint256) {
        Lot[] storage arr = _lots[account];
        uint256 sum;
        uint64 nowTs = uint64(block.timestamp);

        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i].amount != 0 && arr[i].unlockTime > nowTs) {
                sum += uint256(arr[i].amount);
            }
        }
        return sum;
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override {
        require(!registry.isInitialized(owner), "owner-disabled");
        super.permit(owner, spender, value, deadline, v, r, s);
    }

    // --------------------------------------------------------------------
    // Transfers (direct)
    // --------------------------------------------------------------------

    function transfer(address to, uint256 amount) public override returns (bool) {
        require(!registry.isInitialized(msg.sender), "owner-disabled");
        _transferWithInheritance(msg.sender, to, amount, MIN_WAIT_SECONDS, bytes32(0));
        return true;
    }

    function transferWithInheritance(
        address to,
        uint256 amount,
        uint64 waitSeconds,
        bytes32 characteristic
    ) external returns (bool) {
        _transferWithInheritance(msg.sender, to, amount, waitSeconds, characteristic);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 allowanceCur = allowance(from, msg.sender);
        require(allowanceCur >= amount, "insufficient allowance");
        unchecked { _approve(from, msg.sender, allowanceCur - amount); }

        _transferWithInheritance(from, to, amount, MIN_WAIT_SECONDS, bytes32(0));
        return true;
    }

    // --------------------------------------------------------------------
    // Activation: one-shot initKeys + migrate full balance to signingKey
    // --------------------------------------------------------------------

    function activateKeysAndMigrate(address signingKey, address revokeKey) external {
        registry.initKeysFromAdmin(msg.sender, signingKey, revokeKey);

        uint256 bal = balanceOf(msg.sender);
        if (bal > 0) {
            super._transfer(msg.sender, signingKey, bal);

            // make migrated funds immediately spendable under signingKey
            _lots[signingKey].push(
                Lot({
                    senderOwner: address(0),
                    amount: uint128(bal),
                    createdAt: uint64(block.timestamp),
                    minUnlockTime: uint64(block.timestamp),
                    unlockTime: uint64(block.timestamp),
                    characteristic: bytes32(0)
                })
            );
        }
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        require(!registry.isInitialized(msg.sender), "owner-disabled");
        return super.approve(spender, amount);
    }

    // --------------------------------------------------------------------
    // Sender controls (direct)
    // --------------------------------------------------------------------

    function reduceUnlockTime(address recipient, uint256 lotIndex, uint64 newUnlockTime) external {
        Lot storage lot = _lots[recipient][lotIndex];
        require(lot.amount != 0, "empty-lot");

        address owner = lot.senderOwner;
        address rk = registry.revokeKeyOf(owner);
        if (rk != address(0)) {
            require(msg.sender == rk, "not-revoke");
        } else {
            require(msg.sender == owner, "not-sender");
        }

        require(block.timestamp < lot.unlockTime, "already-unlocked");
        require(newUnlockTime < lot.unlockTime, "not-reduction");
        require(newUnlockTime >= lot.minUnlockTime, "below-min");

        uint64 old = lot.unlockTime;
        lot.unlockTime = newUnlockTime;

        emit UnlockTimeReduced(owner, recipient, lotIndex, old, newUnlockTime);
    }


    function revoke(address recipient, uint256 lotIndex) external {
        Lot storage lot = _lots[recipient][lotIndex];
        uint256 amount = uint256(lot.amount);

        require(amount != 0, "empty-lot");

        address owner = lot.senderOwner;
        address rk = registry.revokeKeyOf(owner);
        if (rk != address(0)) {
            require(msg.sender == rk, "not-revoke");
        } else {
            require(msg.sender == owner, "not-sender");
        }

        require(block.timestamp < lot.unlockTime, "already-unlocked");

        lot.amount = 0;

        address refundTo = registry.signingKeyOf(owner);
        if (refundTo == address(0)) refundTo = owner;

        super._transfer(recipient, refundTo, amount);

        _lots[refundTo].push(
            Lot({
                senderOwner: address(0),
                amount: uint128(amount),
                createdAt: uint64(block.timestamp),
                minUnlockTime: uint64(block.timestamp),
                unlockTime: uint64(block.timestamp),
                characteristic: bytes32(0)
            })
        );

        emit Revoked(owner, recipient, lotIndex, amount);
    }
    // --------------------------------------------------------------------
    // Meta-transactions (EIP-712)
    // --------------------------------------------------------------------

    function transferWithInheritanceBySig(
        address from,
        address to,
        uint256 amount,
        uint64 waitSeconds,
        bytes32 characteristic,
        uint256 deadline,
        bytes calldata signature
    ) external {
        require(block.timestamp <= deadline, "expired");
        require(waitSeconds >= MIN_WAIT_SECONDS, "wait-too-short");

        

        uint256 nonce = registry.signingNonceOf(from);

        bytes32 structHash = keccak256(
            abi.encode(
                TRANSFER_TYPEHASH,
                from, to, amount, waitSeconds, characteristic,
                nonce, deadline
            )
        );

        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = digest.recover(signature);

        require(signer == from, "bad-signature");

        registry.useSigningNonce(from, nonce);
        _transferWithInheritance(from, to, amount, waitSeconds, characteristic);
    }

    // --------------------------------------------------------------------
    // Internal mechanics
    // --------------------------------------------------------------------

    function _transferWithInheritance(
        address sender,
        address recipient,
        uint256 amount,
        uint64 waitSeconds,
        bytes32 characteristic
    ) internal {

        // Resolve logical owner (if sender is signingKey)
        address ownerLogical = registry.ownerOfSigningKey(sender);
        if (ownerLogical == address(0)) ownerLogical = sender;

        require(waitSeconds >= MIN_WAIT_SECONDS, "wait-too-short");

        _consumeSpendableLots(sender, amount);

        uint64 nowTs = uint64(block.timestamp);
        uint64 minUnlock = nowTs + MIN_WAIT_SECONDS;
        uint64 unlockAt  = nowTs + waitSeconds;

        _lots[recipient].push(
            Lot({
                senderOwner: ownerLogical,
                amount: uint128(amount),
                createdAt: nowTs,
                minUnlockTime: minUnlock,
                unlockTime: unlockAt,
                characteristic: characteristic
            })
        );

        uint256 lotIndex = _lots[recipient].length - 1;
        super._transfer(sender, recipient, amount);

        emit TransferWithInheritance(
            sender, recipient, amount,
            unlockAt, minUnlock, characteristic, lotIndex
        );
    }

    function _consumeSpendableLots(address owner, uint256 amount) internal {
        Lot[] storage arr = _lots[owner];
        uint256 remaining = amount;
        uint64 nowTs = uint64(block.timestamp);

        for (uint256 i = 0; i < arr.length && remaining > 0; i++) {
            Lot storage lot = arr[i];
            if (lot.amount == 0 || lot.unlockTime > nowTs) continue;

            uint256 lotAmt = uint256(lot.amount);
            if (lotAmt <= remaining) {
                remaining -= lotAmt;
                lot.amount = 0;
            } else {
                lot.amount = uint128(lotAmt - remaining);
                remaining = 0;
            }
        }

        require(remaining == 0, "insufficient-spendable");
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        uint64 nowTs = uint64(block.timestamp);

        _lots[to].push(
            Lot({
                senderOwner: address(0),
                amount: uint128(amount),
                createdAt: nowTs,
                minUnlockTime: nowTs,
                unlockTime: nowTs,
                characteristic: bytes32(0)
            })
        );

        _mint(to, amount);
    }

}
