// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "./interfaces/IINDKeyRegistryLite.sol";
import "./lib/Gregorian.sol";

contract InheritanceDollarVaultUpgradeable is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    EIP712Upgradeable,
    IERC20,
    IERC20Metadata
{
    using Gregorian for uint256;

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint64 public constant MIN_INHERITANCE_WAIT = 1 days;
    uint16 public constant INACTIVITY_YEARS = 7;
    uint16 public constant MAX_WAIT_YEARS = 50;
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    // upper bounds / compatibility guards, NOT final semantic source of truth
    uint64 public constant MAX_INHERITANCE_WAIT = uint64(50 * 366 days);
    uint64 public constant DEAD_AFTER = uint64(7 * 366 days);

    struct Lot {
        address senderOwner;
        uint256 amount;
        uint64 unlockTime;
        uint64 minUnlockTime;
    }

    struct AvgState {
        uint16 year;
        uint64 lastTs;
        uint256 acc;
        uint256 lastBal;
    }

    string private _nameCustom;
    string private _symbolCustom;
    uint8 private constant _DECIMALS = 18;

    uint256 private _totalSupplyCustom;
    uint256 public maxSupply;

    IINDKeyRegistryLite public registry;

    mapping(address => uint256) private _unprotectedBalances;
    mapping(address => Lot[]) private _lots;
    mapping(address => uint256) private _head;
    mapping(address => mapping(address => uint256)) private _allowances;

    // Liveness (AND semantics)
    mapping(address => uint64) private _lastSignedOutTs;
    mapping(address => uint64) private _lastRenewTs;

    mapping(address => address) private _defaultHeir;
    mapping(address => uint256) private _nonces;
    mapping(address => AvgState) private _avg;

    event TransferWithInheritance(
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        uint64 unlockTime,
        uint64 minUnlockTime,
        bytes32 characteristic,
        uint256 lotIndex
    );

    event LotSwept(address indexed recipient, uint256 indexed lotIndex, address indexed to, uint256 amount);
    event DefaultHeirSet(address indexed owner, address indexed heir);
    event AutoSwept(address indexed owner, address indexed to, uint256 amount);
    event Revoked(address indexed senderOwner, address indexed recipient, uint256 indexed lotIndex, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error MaxSupplyExceeded();
    error InsufficientUnprotectedBalance();
    error InsufficientProtectedBalance();
    error InsufficientAllowance();
    error InheritanceWaitTooShort();
    error InheritanceWaitTooLong();
    error RecipientDead();
    error NotRevoke();
    error LotUnlocked();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, uint256 maxSupply_, address registry_) external initializer {
        if (admin == address(0)) revert ZeroAddress();
        if (registry_ == address(0)) revert ZeroAddress();

        __AccessControl_init();
        __EIP712_init("Inheritance Dollar", "1");

        _nameCustom = "Inheritance Dollar";
        _symbolCustom = "IND";
        maxSupply = maxSupply_;
        registry = IINDKeyRegistryLite(registry_);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);

        _touchActive(admin);
    }

    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}

    function _revertOwnerDisabled() private pure {
        assembly {
            mstore(0x00, 0xf28dceb300000000000000000000000000000000000000000000000000000000)
            revert(0x00, 0x04)
        }
    }

    function name() external view override returns (string memory) {
        return _nameCustom;
    }

    function symbol() external view override returns (string memory) {
        return _symbolCustom;
    }

    function decimals() external pure override returns (uint8) {
        return _DECIMALS;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupplyCustom;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _unprotectedBalances[account];
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function nonces(address owner) public view returns (uint256) {
        return _nonces[owner];
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // Compatibility getter used by older tests: returns the max of liveness timestamps
    function lastInteractionOf(address account) external view returns (uint64) {
        address ownerLogical = _logicalOwnerOf(account);
        uint64 a = _lastSignedOutTs[ownerLogical];
        uint64 b = _lastRenewTs[ownerLogical];
        return a >= b ? a : b;
    }

    function lastSignedOutOf(address account) external view returns (uint64) {
        return _lastSignedOutTs[_logicalOwnerOf(account)];
    }

    function lastRenewOf(address account) external view returns (uint64) {
        return _lastRenewTs[_logicalOwnerOf(account)];
    }

    function defaultHeirOf(address owner) external view returns (address) {
        return _defaultHeir[owner];
    }

    // exact gregorian max wait from "now"
    function maxInheritanceWaitNow() external view returns (uint64) {
        uint64 nowTs = uint64(block.timestamp);
        uint64 maxUnlock = _shiftByYears(nowTs, MAX_WAIT_YEARS);
        return maxUnlock - nowTs;
    }

    // exact gregorian death threshold for this owner
    function deathTimestampOf(address account) external view returns (uint64) {
        return _deathTimestampOf(_logicalOwnerOf(account));
    }

    function isDead(address account) public view returns (bool) {
        return _isDead(_logicalOwnerOf(account));
    }

    function headOf(address user) external view returns (uint256) {
        return _head[user];
    }

    function getLots(address user) external view returns (Lot[] memory) {
        return _lots[user];
    }

    function lotOf(address user, uint256 i) external view returns (Lot memory) {
        return _lots[user][i];
    }

    function protectedBalanceOf(address user) public view returns (uint256 total) {
        Lot[] storage l = _lots[user];
        uint256 h = _head[user];
        for (uint256 i = h; i < l.length; i++) {
            total += l[i].amount;
        }
    }

    function spendableBalanceOf(address user) public view returns (uint256 total) {
        Lot[] storage l = _lots[user];
        uint256 h = _head[user];
        for (uint256 i = h; i < l.length; i++) {
            if (block.timestamp >= l[i].unlockTime) {
                total += l[i].amount;
            }
        }
    }

    function lockedBalanceOf(address user) public view returns (uint256 total) {
        Lot[] storage l = _lots[user];
        uint256 h = _head[user];
        for (uint256 i = h; i < l.length; i++) {
            if (block.timestamp < l[i].unlockTime) {
                total += l[i].amount;
            }
        }
    }

    function totalUserBalanceOf(address user) public view returns (uint256) {
        return _unprotectedBalances[user] + protectedBalanceOf(user);
    }

    function averageBalanceThisYear(address user) external view returns (uint256 avg) {
        address owner = _logicalOwnerOf(user);
        AvgState storage st = _avg[owner];

        if (st.lastTs == 0) {
            return totalUserBalanceOf(_primaryAccountOf(owner));
        }

        uint256 acc = st.acc;
        uint64 tNow = uint64(block.timestamp);
        if (tNow > st.lastTs) {
            acc += st.lastBal * uint256(tNow - st.lastTs);
        }

        uint256 bucketStart = Gregorian.yearStartTs(st.year);
        uint256 elapsed = block.timestamp - bucketStart;
        if (elapsed == 0) return st.lastBal;

        avg = acc / elapsed;
    }

    function keepAlive() external returns (bool) {
        _avgAccumulate(msg.sender);
        _touchRenew(msg.sender);
        _avgSetBalance(msg.sender);
        return true;
    }

    function renewLiveness() external returns (bool) {
        _avgAccumulate(msg.sender);
        _touchRenew(msg.sender);
        _avgSetBalance(msg.sender);
        return true;
    }

    function setDefaultHeir(address heir) external returns (bool) {
        if (registry.ownerOfSigningKey(msg.sender) != address(0)) _revertOwnerDisabled();
        if (registry.isInitialized(msg.sender)) _revertOwnerDisabled();

        _defaultHeir[msg.sender] = heir;

        _touchRenew(msg.sender);
        emit DefaultHeirSet(msg.sender, heir);
        return true;
    }

    function revokeSetDefaultHeir(address owner, address newHeir) external returns (bool) {
        address rk = registry.revokeKeyOf(owner);
        if (rk == address(0) || msg.sender != rk) revert NotRevoke();

        _defaultHeir[owner] = newHeir;
        emit DefaultHeirSet(owner, newHeir);
        return true;
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 sSig)
        public
    {
        if (registry.isInitialized(owner)) _revertOwnerDisabled();
        require(block.timestamp <= deadline, "expired");

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _nonces[owner], deadline));

        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, v, r, sSig);
        require(signer == owner, "bad-signature");

        unchecked {
            _nonces[owner] += 1;
        }

        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        address owner = msg.sender;
        if (registry.isInitialized(owner)) _revertOwnerDisabled();

        _allowances[owner][spender] = amount;
        _touchRenew(owner);
        emit Approval(owner, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        address sender = msg.sender;
        _avgAccumulate(sender);
        if (registry.isInitialized(sender)) _revertOwnerDisabled();
        if (to == address(0)) revert ZeroAddress();

        address rawTarget = _resolveRecipientRaw(to);
        address targetOwner = _logicalOwnerOf(rawTarget);

        _avgAccumulate(targetOwner);
        _autoSweepIfDead(targetOwner);

        if (_isDead(targetOwner)) {
            _touchActive(sender);
            _avgSetBalance(sender);
            _avgSetBalance(targetOwner);
            return true;
        }

        _transferUnprotected(sender, rawTarget, amount);
        _touchActive(sender);
        _avgSetBalance(sender);
        _avgSetBalance(targetOwner);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        _avgAccumulate(from);
        if (registry.isInitialized(from)) _revertOwnerDisabled();
        if (to == address(0)) revert ZeroAddress();

        uint256 a = _allowances[from][msg.sender];
        if (a < amount) revert InsufficientAllowance();

        unchecked {
            _allowances[from][msg.sender] = a - amount;
        }
        emit Approval(from, msg.sender, _allowances[from][msg.sender]);

        address rawTarget = _resolveRecipientRaw(to);
        address targetOwner = _logicalOwnerOf(rawTarget);

        _avgAccumulate(targetOwner);
        _autoSweepIfDead(targetOwner);

        if (_isDead(targetOwner)) {
            _touchActive(from);
            _avgSetBalance(from);
            _avgSetBalance(targetOwner);
            return true;
        }

        _transferUnprotected(from, rawTarget, amount);
        _touchActive(from);
        _avgSetBalance(from);
        _avgSetBalance(targetOwner);
        return true;
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (_totalSupplyCustom + amount > maxSupply) revert MaxSupplyExceeded();

        address resolved = _resolveRecipientRaw(to);
        _avgAccumulate(resolved);

        _totalSupplyCustom += amount;
        _unprotectedBalances[resolved] += amount;

        _avgSetBalance(resolved);
        emit Transfer(address(0), resolved, amount);
    }

    function protect(uint256 amount) external returns (bool) {
        if (amount == 0) revert ZeroAmount();

        address sender = msg.sender;
        _avgAccumulate(sender);
        if (registry.isInitialized(sender)) _revertOwnerDisabled();
        if (_unprotectedBalances[sender] < amount) revert InsufficientUnprotectedBalance();

        _unprotectedBalances[sender] -= amount;

        _lots[sender].push(
            Lot({
                senderOwner: address(0),
                amount: amount,
                unlockTime: uint64(block.timestamp),
                minUnlockTime: uint64(block.timestamp)
            })
        );

        _touchActive(sender);
        _avgSetBalance(sender);
        return true;
    }

    function unprotect(uint256 amount) external returns (bool) {
        if (amount == 0) revert ZeroAmount();

        address sender = msg.sender;
        _avgAccumulate(sender);
        if (registry.isInitialized(sender)) _revertOwnerDisabled();

        _autoSweepIfDead(_logicalOwnerOf(sender));
        _consumeSpendableLots(sender, amount);
        _unprotectedBalances[sender] += amount;

        _touchActive(sender);
        _avgSetBalance(sender);
        return true;
    }

    function transferWithInheritance(address to, uint256 amount, uint64 waitSeconds, bytes32 characteristic)
        external
        returns (bool)
    {
        if (waitSeconds < MIN_INHERITANCE_WAIT) revert InheritanceWaitTooShort();

        uint64 nowTs = uint64(block.timestamp);
        uint64 maxUnlock = _shiftByYears(nowTs, MAX_WAIT_YEARS);
        if (nowTs + waitSeconds > maxUnlock) revert InheritanceWaitTooLong();

        address sender = msg.sender;
        if (registry.isInitialized(sender)) _revertOwnerDisabled();
        if (to == address(0)) revert ZeroAddress();

        address rawTarget = _resolveRecipientRaw(to);
        address targetOwner = _logicalOwnerOf(rawTarget);

        _autoSweepIfDead(targetOwner);
        _autoSweepIfDead(_logicalOwnerOf(sender));
        _consumeSpendableLots(sender, amount);
        _touchActive(sender);

        // invio a morto: il nuovo valore torna subito spendibile al mittente
        if (_isDead(targetOwner)) {
            _lots[sender].push(Lot({senderOwner: address(0), amount: amount, unlockTime: nowTs, minUnlockTime: nowTs}));
            return true;
        }

        uint64 unlockTime = nowTs + waitSeconds;

        _lots[rawTarget].push(
            Lot({
                senderOwner: _logicalOwnerOf(sender), amount: amount, unlockTime: unlockTime, minUnlockTime: unlockTime
            })
        );

        emit TransferWithInheritance(
            sender, rawTarget, amount, unlockTime, unlockTime, characteristic, _lots[rawTarget].length - 1
        );

        return true;
    }

    function revoke(address recipient, uint256 lotIndex) external returns (bool) {
        Lot[] storage l = _lots[recipient];
        if (lotIndex >= l.length) revert InsufficientProtectedBalance();

        Lot storage lot = l[lotIndex];
        uint256 amount = lot.amount;
        if (amount == 0) revert InsufficientProtectedBalance();
        if (block.timestamp >= lot.unlockTime) revert LotUnlocked();

        address senderOwner = lot.senderOwner;
        address rk = senderOwner == address(0) ? address(0) : registry.revokeKeyOf(senderOwner);
        if (rk == address(0) || msg.sender != rk) revert NotRevoke();

        lot.amount = 0;
        _advanceHead(recipient);

        address refundTo = _primaryAccountOf(senderOwner);
        _unprotectedBalances[refundTo] += amount;

        emit Transfer(recipient, refundTo, amount);
        emit Revoked(senderOwner, recipient, lotIndex, amount);
        return true;
    }

    function sweepLot(address recipient, uint256 lotIndex) external {
        address ownerLogical = _logicalOwnerOf(recipient);
        if (!_isDead(ownerLogical)) revert RecipientDead();

        Lot[] storage l = _lots[recipient];
        if (lotIndex >= l.length) revert InsufficientProtectedBalance();

        Lot storage lot = l[lotIndex];
        uint256 amount = lot.amount;
        if (amount == 0) revert InsufficientProtectedBalance();
        if (block.timestamp < lot.unlockTime) revert InsufficientProtectedBalance();

        lot.amount = 0;

        if (lotIndex == _head[recipient]) {
            _advanceHead(recipient);
        }

        address target = _inheritanceTarget(ownerLogical);
        if (target == address(0)) {
            _totalSupplyCustom -= amount;
            emit Transfer(recipient, address(0), amount);
            emit LotSwept(recipient, lotIndex, address(0), amount);
        } else {
            _unprotectedBalances[target] += amount;
            emit Transfer(recipient, target, amount);
            emit LotSwept(recipient, lotIndex, target, amount);
        }
    }

    function autoSweepIfDead(address owner) external returns (uint256 swept) {
        return _autoSweepIfDead(_logicalOwnerOf(owner));
    }

    function _autoSweepIfDead(address ownerLogical) internal returns (uint256 swept) {
        if (!_isDead(ownerLogical)) return 0;

        address account = _primaryAccountOf(ownerLogical);
        Lot[] storage l = _lots[account];
        uint256 i = _head[account];
        uint256 len = l.length;

        while (i < len) {
            Lot storage lot = l[i];
            if (lot.amount == 0) {
                unchecked {
                    ++i;
                }
                continue;
            }
            if (block.timestamp < lot.unlockTime) break;

            swept += lot.amount;
            lot.amount = 0;
            unchecked {
                ++i;
            }
        }

        _head[account] = i;

        if (swept == 0) return 0;

        address target = _inheritanceTarget(ownerLogical);
        if (target == address(0)) {
            _totalSupplyCustom -= swept;
            emit Transfer(account, address(0), swept);
            emit AutoSwept(ownerLogical, address(0), swept);
        } else {
            _unprotectedBalances[target] += swept;
            emit Transfer(account, target, swept);
            emit AutoSwept(ownerLogical, target, swept);
        }
    }

    function _inheritanceTarget(address ownerLogical) internal view returns (address) {
        address heir = _defaultHeir[ownerLogical];
        if (heir == address(0)) return address(0);

        address heirLogical = _logicalOwnerOf(heir);
        if (_isDead(heirLogical)) return address(0);

        return _resolveRecipientRaw(heir);
    }

    function _primaryAccountOf(address ownerLogical) internal view returns (address) {
        address sk = registry.signingKeyOf(ownerLogical);
        if (sk != address(0)) return sk;
        return ownerLogical;
    }

    function _resolveInboundTarget(address to) internal returns (address resolved, bool burnIt) {
        if (to == address(0)) revert ZeroAddress();

        resolved = _resolveRecipientRaw(to);
        address ownerLogical = _logicalOwnerOf(resolved);

        _autoSweepIfDead(ownerLogical);

        if (_isDead(ownerLogical)) {
            address target = _inheritanceTarget(ownerLogical);
            if (target == address(0)) {
                return (address(0), true);
            }
            return (target, false);
        }

        return (resolved, false);
    }

    function _advanceHead(address user) internal {
        uint256 i = _head[user];
        Lot[] storage l = _lots[user];
        while (i < l.length && l[i].amount == 0) {
            unchecked {
                ++i;
            }
        }
        _head[user] = i;
    }

    function _consumeSpendableLots(address user, uint256 amount) internal {
        uint256 remaining = amount;
        uint256 i = _head[user];
        Lot[] storage l = _lots[user];

        while (remaining > 0 && i < l.length) {
            Lot storage lot = l[i];

            if (block.timestamp < lot.unlockTime) break;

            if (lot.amount <= remaining) {
                remaining -= lot.amount;
                lot.amount = 0;
                unchecked {
                    ++i;
                }
            } else {
                lot.amount -= remaining;
                remaining = 0;
            }
        }

        if (remaining > 0) revert InsufficientProtectedBalance();

        _head[user] = i;
    }

    function _resolveRecipientRaw(address to) internal view returns (address) {
        if (to == address(0)) revert ZeroAddress();

        if (registry.isInitialized(to)) {
            address sk = registry.signingKeyOf(to);
            if (sk != address(0)) return sk;
        }
        return to;
    }

    function _logicalOwnerOf(address a) internal view returns (address) {
        address o = registry.ownerOfSigningKey(a);
        if (o != address(0)) return o;
        return a;
    }

    function _transferUnprotected(address from, address to, uint256 amount) internal {
        if (_unprotectedBalances[from] < amount) revert InsufficientUnprotectedBalance();

        _unprotectedBalances[from] -= amount;
        _unprotectedBalances[to] += amount;

        emit Transfer(from, to, amount);
    }

    function _burnFromUnprotected(address from, uint256 amount) internal {
        if (_unprotectedBalances[from] < amount) revert InsufficientUnprotectedBalance();

        _unprotectedBalances[from] -= amount;
        _totalSupplyCustom -= amount;

        emit Transfer(from, address(0), amount);
    }

    function _avgAccumulate(address actor) internal {
        address owner = _logicalOwnerOf(actor);
        if (owner == address(0)) return;

        AvgState storage st = _avg[owner];
        uint16 yNow = uint256(block.timestamp).yearOf();
        uint64 tNow = uint64(block.timestamp);
        uint256 balNow = totalUserBalanceOf(_primaryAccountOf(owner));
        uint64 yStart = uint64(Gregorian.yearStartTs(yNow));

        if (st.lastTs == 0) {
            st.year = yNow;
            st.lastTs = tNow;
            st.lastBal = balNow;
            st.acc = balNow * uint256(tNow - yStart);
            return;
        }

        if (st.year != yNow) {
            st.year = yNow;
            st.lastTs = tNow;
            st.lastBal = balNow;
            st.acc = balNow * uint256(tNow - yStart);
            return;
        }

        if (tNow > st.lastTs) {
            st.acc += st.lastBal * uint256(tNow - st.lastTs);
            st.lastTs = tNow;
        }
    }

    function _avgSetBalance(address actor) internal {
        address owner = _logicalOwnerOf(actor);
        if (owner == address(0)) return;

        AvgState storage st = _avg[owner];
        uint16 yNow = uint256(block.timestamp).yearOf();
        uint64 tNow = uint64(block.timestamp);
        uint256 balNow = totalUserBalanceOf(_primaryAccountOf(owner));
        uint64 yStart = uint64(Gregorian.yearStartTs(yNow));

        if (st.lastTs == 0) {
            st.year = yNow;
            st.lastTs = tNow;
            st.lastBal = balNow;
            st.acc = balNow * uint256(tNow - yStart);
            return;
        }

        if (st.year != yNow) {
            st.year = yNow;
            st.lastTs = tNow;
            st.lastBal = balNow;
            st.acc = balNow * uint256(tNow - yStart);
            return;
        }

        st.lastBal = balNow;
    }

    function debugAvg(address user)
        external
        view
        returns (
            uint16 year,
            uint64 lastTs,
            uint256 acc,
            uint256 lastBal,
            address ownerLogical,
            address primaryAccount,
            uint256 totalNow
        )
    {
        ownerLogical = _logicalOwnerOf(user);
        primaryAccount = _primaryAccountOf(ownerLogical);
        AvgState storage st = _avg[ownerLogical];
        year = st.year;
        lastTs = st.lastTs;
        acc = st.acc;
        lastBal = st.lastBal;
        totalNow = totalUserBalanceOf(primaryAccount);
    }

    function _touchSignedOut(address actor) internal {
        address owner = _logicalOwnerOf(actor);
        _lastSignedOutTs[owner] = uint64(block.timestamp);
    }

    function _touchRenew(address actor) internal {
        address owner = _logicalOwnerOf(actor);
        _lastRenewTs[owner] = uint64(block.timestamp);
    }

    function _touchActive(address actor) internal {
        address owner = _logicalOwnerOf(actor);
        uint64 nowTs = uint64(block.timestamp);
        _lastSignedOutTs[owner] = nowTs;
        _lastRenewTs[owner] = nowTs;
    }

    function _deathTimestampOf(address ownerLogical) internal view returns (uint64) {
        uint64 a = _lastSignedOutTs[ownerLogical];
        uint64 b = _lastRenewTs[ownerLogical];
        if (a == 0 || b == 0) return 0;

        uint64 da = _shiftByYears(a, INACTIVITY_YEARS);
        uint64 db = _shiftByYears(b, INACTIVITY_YEARS);
        return da >= db ? da : db;
    }

    function _isDead(address ownerLogical) internal view returns (bool) {
        uint64 deathTs = _deathTimestampOf(ownerLogical);
        if (deathTs == 0) return false;
        return uint64(block.timestamp) > deathTs;
    }

    /// @dev shift by gregorian years preserving intra-year offset, clamp at year end if needed
    function _shiftByYears(uint64 baseTs, uint16 deltaYears) internal pure returns (uint64) {
        uint16 y = uint256(baseTs).yearOf();

        uint256 start = Gregorian.yearStartTs(y);
        while (start > uint256(baseTs)) {
            unchecked {
                y--;
            }
            start = Gregorian.yearStartTs(y);
        }

        uint256 end_ = Gregorian.yearEndTs(y);
        while (uint256(baseTs) >= end_) {
            unchecked {
                y++;
            }
            start = end_;
            end_ = Gregorian.yearEndTs(y);
        }

        uint256 offset = uint256(baseTs) - start;
        uint16 targetYear = y + deltaYears;

        uint256 tStart = Gregorian.yearStartTs(targetYear);
        uint256 tEnd = Gregorian.yearEndTs(targetYear);

        uint256 shifted = tStart + offset;
        if (shifted >= tEnd) shifted = tEnd - 1;

        return uint64(shifted);
    }

    uint256[46] private __gap;
}
