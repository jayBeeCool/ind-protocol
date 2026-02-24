// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./lib/Gregorian.sol";

contract INDKeyRegistry is AccessControl {
    bytes32 public constant REGISTRY_ADMIN_ROLE = keccak256("REGISTRY_ADMIN_ROLE");

    struct Keys {
        address signingKey;
        address revokeKey;
        uint256 signingNonce;
        uint256 revokeNonce;
        bool initialized;
    }

    mapping(address => Keys) private _keys;
    mapping(address => address) private _ownerOfSigning;
    mapping(address => address) private _ownerOfRevoke;

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

    function ownerOfRevokeKey(address revokeKey) external view returns (address) {
        return _ownerOfRevoke[revokeKey];
    }

    function initKeysFromAdmin(address owner, address signingKey, address revokeKey)
        external
        onlyRole(REGISTRY_ADMIN_ROLE)
    {
        require(owner != address(0), "owner=0");
        require(signingKey != address(0), "signingKey=0");
        require(revokeKey != address(0), "revokeKey=0");
        require(signingKey != revokeKey, "keys-equal");
        require(_ownerOfSigning[signingKey] == address(0), "signingKey-in-use");
        require(_ownerOfRevoke[revokeKey] == address(0), "revokeKey-in-use");

        Keys storage k = _keys[owner];
        require(!k.initialized, "already-initialized");

        k.signingKey = signingKey;
        k.revokeKey = revokeKey;
        k.signingNonce = 0;
        k.revokeNonce = 0;
        k.initialized = true;

        _ownerOfSigning[signingKey] = owner;
        _ownerOfRevoke[revokeKey] = owner;

        emit KeysInitialized(owner, signingKey, revokeKey);
    }

    function useSigningNonce(address owner, uint256 expected) external onlyRole(REGISTRY_ADMIN_ROLE) {
        Keys storage k = _keys[owner];
        require(k.signingNonce == expected, "bad-signing-nonce");
        k.signingNonce++;
        emit SigningNonceUsed(owner, expected);
    }

    function useRevokeNonce(address owner, uint256 expected) external onlyRole(REGISTRY_ADMIN_ROLE) {
        Keys storage k = _keys[owner];
        require(k.revokeNonce == expected, "bad-revoke-nonce");
        k.revokeNonce++;
        emit RevokeNonceUsed(owner, expected);
    }

    function rotateSigning(address owner, address newSigning) external {
        require(newSigning != address(0), "signingKey=0");
        require(_ownerOfSigning[newSigning] == address(0), "signingKey-in-use");

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
        require(_ownerOfRevoke[newRevoke] == address(0), "revokeKey-in-use");

        Keys storage k = _keys[owner];
        require(k.initialized, "not-initialized");
        require(msg.sender == k.revokeKey, "not-revoke");

        address old = k.revokeKey;
        delete _ownerOfRevoke[old];
        _ownerOfRevoke[newRevoke] = owner;
        k.revokeKey = newRevoke;

        k.revokeNonce++;
        emit RevokeKeyRotated(owner, old, newRevoke, k.revokeNonce - 1);
    }
}

contract InheritanceDollar is ERC20Permit, AccessControl {
    /* Legacy compatibility type: Lot (type-only; storage is in step4 mappings) */
    struct Lot {
        address senderOwner;
        uint128 amount;
        uint64 createdAt;
        uint64 minUnlockTime;
        uint64 unlockTime;
        bytes32 characteristic;
    }

    using ECDSA for bytes32;
    using Gregorian for uint256;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint64 public constant MIN_WAIT_SECONDS = 86400;
    uint64 public constant MAX_WAIT_SECONDS = 50 * 365 days;
    uint64 public constant DEAD_AFTER_SECONDS = 7 * 365 days;

    INDKeyRegistry public immutable registry;

    // --------------------------------------------------------------------
    // STEP 1/4: Spendable accounting (double-queue foundation)
    // For now: ALL ERC20 balance is considered spendable.
    // Later steps will move value between spendable and locked buckets.
    // --------------------------------------------------------------------
    mapping(address => uint256) private _spendable;

    // --------------------------------------------------------------------
    // STEP 2/4: Locked buckets (1h) + cursor for maturation
    // locked is aggregated per-hour to avoid per-lot scans.
    // --------------------------------------------------------------------
    mapping(address => mapping(uint32 => uint256)) private _locked1h; // owner => hourKey => lockedAmount
    mapping(address => uint32) private _bucketCursor1h;               // owner => earliest hourKey not yet processed

    struct SpendNode { uint256 amount; uint64 next; }
    mapping(address => mapping(uint64 => SpendNode)) private _spendNode;
    mapping(address => uint64) private _spendHead;
    mapping(address => uint64) private _spendTail;
    mapping(address => uint64) private _spendSeq;




    // ---------------------------
    // TODO: storage rewrite here:
    // - pending (revocable) locked indexed by 1h buckets
    // - spendable aggregated (no per-lot list)
    // - optional linked list for FIFO if needed
    // - packed structs (1 slot)
    // ---------------------------

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
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }


    // --------------------------------------------------------------------
    // STEP 1/4: Public views (compatibility helpers)
    // --------------------------------------------------------------------

    function spendableBalanceOf(address account) public view returns (uint256) {
        return _spendable[account];
    }

    function lockedBalanceOf(address account) public view returns (uint256) {
        uint256 bal = balanceOf(account);
        uint256 sp = _spendable[account];
        if (bal > sp) return bal - sp;
        return 0;
    }

    // --------------------------------------------------------------------
    // STEP 1/4: Central hook for ALL balance changes
    // For now, everything is spendable so _spendable mirrors ERC20 balance.
    // --------------------------------------------------------------------

    // --------------------------------------------------------------------
    // STEP 2/4: 1h bucket maturation helpers
    // --------------------------------------------------------------------

    function _hourKey1h(uint64 ts) internal pure returns (uint32) {
        return uint32(uint256(ts) / 3600);
    }

    function _promoteUnlocked(address owner) internal {
        uint32 nowKey = _hourKey1h(uint64(block.timestamp));
        uint32 cur = _bucketCursor1h[owner];
        if (cur == 0) cur = nowKey; // lazy init

        // Move matured buckets (<= nowKey) into spendable
        while (cur <= nowKey) {
            uint256 amt = _locked1h[owner][cur];
            if (amt != 0) {
                delete _locked1h[owner][cur];
                _qPush(owner, amt);
            }
            unchecked { cur++; }
        }
        _bucketCursor1h[owner] = cur;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);

        // STEP 2: mature unlocked buckets whenever an account is touched
        if (from != address(0)) _promoteUnlocked(from);
        if (to != address(0)) _promoteUnlocked(to);

        if (from != address(0)) {
            _qConsume(from, value);
        }
        if (to != address(0)) {
            _qPush(to, value);
        }
    }


    function _qPush(address owner, uint256 amt) internal {
        if (amt == 0) return;
        uint64 id = ++_spendSeq[owner];
        _spendNode[owner][id] = SpendNode({amount: amt, next: 0});
        uint64 t = _spendTail[owner];
        if (t == 0) {
            _spendHead[owner] = id;
            _spendTail[owner] = id;
        } else {
            _spendNode[owner][t].next = id;
            _spendTail[owner] = id;
        }
        _qPush(owner, amt);
    }

    function _qConsume(address owner, uint256 amt) internal {
        if (amt == 0) return;
        require(_spendable[owner] >= amt, "spendable-underflow");
        _spendable[owner] -= amt;

        uint64 h = _spendHead[owner];
        while (amt > 0) {
            require(h != 0, "spendable-empty");
            SpendNode storage n = _spendNode[owner][h];
            uint256 a = n.amount;
            if (a <= amt) {
                amt -= a;
                uint64 nx = n.next;
                delete _spendNode[owner][h];
                h = nx;
            } else {
                n.amount = a - amt;
                amt = 0;
            }
        }
        _spendHead[owner] = h;
        if (h == 0) _spendTail[owner] = 0;
    }

}
