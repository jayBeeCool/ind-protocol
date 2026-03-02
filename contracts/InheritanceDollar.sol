// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Gregorian} from "./lib/Gregorian.sol";
import {INDKeyRegistry} from "./INDKeyRegistry.sol";

contract InheritanceDollar is ERC20Permit, AccessControl {
    error RecipientDead();

    using ECDSA for bytes32;
    using Gregorian for uint256;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint64 public constant MIN_WAIT_SECONDS = 86400; // 24 hours

    // Calendar-year based thresholds (Gregorian)
    uint16 public constant INACTIVITY_YEARS = 7;
    uint16 public constant MAX_WAIT_YEARS = 50;
    uint64 public constant DEAD_AFTER_SECONDS = uint64(7 * 365 days);

    // F03: account considered dead if no *signed outgoing* activity for this period

    // Anti-abuse: cap maximum inheritance wait (upper bound; includes leap years)
    uint64 public constant MAX_WAIT_SECONDS = uint64(50 * 366 days);

    // Liveness tracking: last year an owner signed/spent
    uint256 public constant MAX_SUPPLY = type(uint128).max;

    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    // keep name "registry" for backward compatibility

    // forge-lint: disable-next-line(screaming-snake-case-immutable)

    // keep name "registry" for backward compatibility
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    INDKeyRegistry public immutable registry;

    // --------------------------------------------------------------------
    // F2: lifecycle + default heir (S1) + liveness + time-weighted average
    // --------------------------------------------------------------------

    // Default heir per logical owner (last resort before burn when both sender+recipient are dead)
    mapping(address => address) private _defaultHeir;

    // "Alive" is defined ONLY by spend actions (transfer/revoke/kill-switch/metatx),
    // NOT by receiving funds. Stored as last spend YEAR (Gregorian, UTC).

    struct AvgState {
        uint16 year; // current Gregorian year bucket (UTC)
        uint64 lastTs; // last timestamp we accounted up to
        uint256 acc; // accumulated (balance * dt) within current year
        uint256 lastBal; // balance snapshot as-of lastTs
    }

    mapping(address => AvgState) private _avg;

    event DefaultHeirSet(address indexed owner, address indexed heir);
    event LotSwept(
        address indexed recipient, uint256 indexed lotIndex, address indexed to, uint256 amount, bytes32 action
    );

    function defaultHeirOf(address owner) external view returns (address) {
        return _defaultHeir[owner];
    }

    function lastSpendYearOf(address owner) external view returns (uint16) {}

    struct Lot {
        address senderOwner; // original sender (controls reduce/revoke)
        uint128 amount;
        uint64 createdAt;
        uint64 minUnlockTime; // createdAt + 86400
        uint64 unlockTime;
        bytes32 characteristic;
    }

    mapping(address => Lot[]) private _lots;
    mapping(address => uint256) private _head;

    // F03: last time an owner signingKey performed a signed outgoing action
    mapping(address => uint64) private _lastSignedOutTs;
    mapping(address => uint64) private _lastRenewTs;

    // -------- EIP-712 typehashes --------
    bytes32 private constant TRANSFER_TYPEHASH = keccak256(
        "TransferInheritance(address from,address to,uint256 amount,uint64 waitSeconds,bytes32 characteristic,uint256 nonce,uint256 deadline)"
    );

    bytes32 private constant REDUCE_TYPEHASH = keccak256(
        "ReduceUnlockTime(address sender,address recipient,uint256 lotIndex,uint64 newUnlockTime,uint256 nonce,uint256 deadline)"
    );

    bytes32 private constant REVOKE_TYPEHASH =
        keccak256("RevokeLot(address sender,address recipient,uint256 lotIndex,uint256 nonce,uint256 deadline)");

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

    event Revoked(address indexed sender, address indexed recipient, uint256 indexed lotIndex, uint256 amount);

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
    // Owner-receive safety: if someone sends/mints to an initialized owner address,
    // redirect to its signingKey so funds are never trapped on owner-disabled address.
    // --------------------------------------------------------------------
    function _resolveRecipient(address to) internal view returns (address) {
        if (to == address(0)) return to;

        // If logical owner initialized → redirect to signingKey
        if (registry.isInitialized(to)) {
            return registry.signingKeyOf(to);
        }

        // If valid signing key → allowed
        if (registry.ownerOfSigningKey(to) != address(0)) {
            return to;
        }

        // Otherwise allow raw addresses (uninitialized owner or external address)
        return to;
    }

    // --------------------------------------------------------------------
    // Views
    // --------------------------------------------------------------------

    /// @notice Standard getter for a single lot (tuple-return, test/audit friendly).
    function lotOf(address recipient, uint256 lotIndex)
        external
        view
        returns (
            address senderOwner,
            uint256 amountRemaining,
            uint64 unlockTime,
            uint64 minUnlockTime,
            bytes32 characteristic
        )
    {
        require(lotIndex < _lots[recipient].length, "lotIndex-oob");
        Lot storage lot = _lots[recipient][lotIndex];
        return (lot.senderOwner, lot.amount, lot.unlockTime, lot.minUnlockTime, lot.characteristic);
    }

    function getLots(address account) external view returns (Lot[] memory) {
        return _lots[account];
    }

    function headOf(address account) external view returns (uint256) {
        return _head[account];
    }

    function spendableBalanceOf(address account) public view returns (uint256) {
        Lot[] storage arr = _lots[account];
        uint256 sum;
        uint64 nowTs = uint64(block.timestamp);
        uint256 h = _head[account];
        uint256 len = arr.length;

        for (uint256 i = h; i < len; ++i) {
            Lot storage lot = arr[i];
            if (lot.amount != 0 && lot.unlockTime <= nowTs) {
                sum += lot.amount;
            }
        }
        return sum;
    }

    function lockedBalanceOf(address account) public view returns (uint256) {
        Lot[] storage arr = _lots[account];
        uint256 sum;
        uint64 nowTs = uint64(block.timestamp);
        uint256 h = _head[account];
        uint256 len = arr.length;

        for (uint256 i = h; i < len; ++i) {
            Lot storage lot = arr[i];
            if (lot.amount != 0 && lot.unlockTime > nowTs) {
                sum += lot.amount;
            }
        }
        return sum;
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
        override
    {
        require(!registry.isInitialized(owner), "owner-disabled");
        super.permit(owner, spender, value, deadline, v, r, s);
    }

    // --------------------------------------------------------------------
    // Transfers (direct)
    // --------------------------------------------------------------------

    function transfer(address to, uint256 amount) public override returns (bool) {
        address owner = _logicalOwnerOf(msg.sender);
        if (registry.ownerOfSigningKey(msg.sender) != address(0)) _touchSignedOut(owner);

        require(!registry.isInitialized(msg.sender), "owner-disabled");
        _touchSpend(msg.sender);
        _transferWithInheritance(msg.sender, to, amount, MIN_WAIT_SECONDS, bytes32(0));

        return true;
    }

    function transferWithInheritance(address to, uint256 amount, uint64 waitSeconds, bytes32 characteristic)
        external
        returns (bool)
    {
        require(!registry.isInitialized(msg.sender), "owner-disabled");
        _transferWithInheritance(msg.sender, to, amount, waitSeconds, characteristic);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        require(!registry.isInitialized(from), "owner-disabled");
        uint256 allowanceCur = allowance(from, msg.sender);
        require(allowanceCur >= amount, "insufficient allowance");
        unchecked {
            _approve(from, msg.sender, allowanceCur - amount);
        }

        _transferWithInheritance(from, to, amount, MIN_WAIT_SECONDS, bytes32(0));

        return true;
    }

    // --------------------------------------------------------------------
    // Activation: one-shot initKeys + migrate full balance to signingKey
    // --------------------------------------------------------------------

    function _activateKeysAndMigrate(address signingKey, address revokeKey) internal {
        registry.initKeysFromAdmin(msg.sender, signingKey, revokeKey);

        // enrollment: initialize annual bucket for inactivity tracking
        _avgAccumulate(msg.sender);
        // enrollment: start inactivity timer at activation
        // enrollment: start inactivity timer at activation
        // Enrollment: starting liveness timer at activation (so inactivity can be detected even if never spent)
        uint256 bal = balanceOf(msg.sender);
        if (bal > 0) {
            super._transfer(msg.sender, signingKey, bal);

            // clear sender lots to keep balance invariants consistent after full migration
            Lot[] storage oldLots = _lots[msg.sender];
            for (uint256 i = _head[msg.sender]; i < oldLots.length; i++) {
                oldLots[i].amount = 0;
            }
            _head[msg.sender] = oldLots.length;

            // make migrated funds immediately spendable under signingKey
            _lots[signingKey].push(
                Lot({
                    senderOwner: address(0),
                    // casting to uint128 is safe because MAX_SUPPLY == type(uint128).max
                    // forge-lint: disable-next-line(unsafe-typecast)
                    amount: uint128(bal),
                    createdAt: uint64(block.timestamp),
                    minUnlockTime: uint64(block.timestamp),
                    unlockTime: uint64(block.timestamp),
                    characteristic: bytes32(0)
                })
            );
        }
    }

    function activateKeysAndMigrate(address signingKey, address revokeKey) external {
        _activateKeysAndMigrate(signingKey, revokeKey);
    }

    function activateKeysAndMigrateWithHeir(address signingKey, address revokeKey, address defaultHeir) external {
        _activateKeysAndMigrate(signingKey, revokeKey);
        if (defaultHeir != address(0)) {
            address heirOwner = _logicalOwnerOf(defaultHeir);
            require(!_isDead(heirOwner), "heir-dead");
            _defaultHeir[msg.sender] = defaultHeir;
            emit DefaultHeirSet(msg.sender, defaultHeir);
        }
    }

    function revokeSetDefaultHeir(address owner, address newHeir) external {
        // only the owner's revokeKey can change default heir (absolute power)
        address rk = registry.revokeKeyOf(owner);
        require(rk != address(0), "no-revoke");
        require(msg.sender == rk, "not-revoke");
        if (newHeir != address(0)) {
            address heirOwner = _logicalOwnerOf(newHeir);
            require(!_isDead(heirOwner), "heir-dead");
        }
        _defaultHeir[owner] = newHeir;
        emit DefaultHeirSet(owner, newHeir);
        // note: does NOT count as spend (no funds moved)
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        require(!registry.isInitialized(msg.sender), "owner-disabled");
        return super.approve(spender, amount);
    }

    // --------------------------------------------------------------------
    // Sender controls (direct)
    // --------------------------------------------------------------------

    // --------------------------------------------------------------------
    // F2: permissionless sweep (post-unlock) for dead accounts + default heir S1
    // --------------------------------------------------------------------

    function sweepLot(address recipient, uint256 lotIndex) external {
        Lot storage lot = _lots[recipient][lotIndex];
        uint256 amount = uint256(lot.amount);
        require(amount != 0, "empty-lot");

        require(block.timestamp >= lot.unlockTime, "not-unlocked");

        address recipOwner = _logicalOwnerOf(recipient);
        require(_isDead(recipOwner), "recipient-alive");

        address senderOwner = lot.senderOwner; // logical owner already stored
        bool senderDead = (senderOwner == address(0)) ? true : _isDead(senderOwner);

        lot.amount = 0;

        if (!senderDead) {
            // refund to sender (to its signingKey if exists, else to owner)
            address refundTo = registry.signingKeyOf(senderOwner);
            if (refundTo == address(0)) refundTo = senderOwner;

            super._transfer(recipient, refundTo, amount);

            // make refunded funds immediately spendable under refundTo
            _lots[refundTo].push(
                Lot({
                    senderOwner: address(0),
                    // casting to uint128 is safe because MAX_SUPPLY == type(uint128).max
                    // forge-lint: disable-next-line(unsafe-typecast)
                    amount: uint128(amount),
                    createdAt: uint64(block.timestamp),
                    minUnlockTime: uint64(block.timestamp),
                    unlockTime: uint64(block.timestamp),
                    characteristic: bytes32(0)
                })
            );

            emit LotSwept(
                recipient,
                lotIndex,
                refundTo,
                amount, // safe literal tag
                // forge-lint: disable-next-line(unsafe-typecast)
                bytes32("REFUND")
            );
            return;
        }

        // both dead -> defaultHeir S1 (last resort) then burn
        address heir = _defaultHeir[recipOwner];
        if (heir != address(0)) {
            address heirOwner = _logicalOwnerOf(heir);
            if (heirOwner == address(0) || !_isDead(heirOwner)) {
                /* compute actual receiver first */
                super._transfer(recipient, heir, amount);

                // forge-lint: disable-next-line(unsafe-typecast)
                // safe: "HEIR" is 4 bytes <= 32 bytes

                // forge-lint: disable-next-line(unsafe-typecast)

                // safe: "HEIR" is 4 bytes <= 32 bytes

                // safe: "HEIR" is 4 bytes <= 32 bytes
                // forge-lint: disable-next-line(unsafe-typecast)
                emit LotSwept(recipient, lotIndex, heir, amount, bytes32("HEIR"));
                return;
            }
        }

        // burn
        _burn(recipient, amount);
        emit LotSwept(
            recipient,
            lotIndex,
            address(0),
            amount, // safe literal tag
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes32("BURN")
        );
    }

    function reduceUnlockTime(address recipient, uint256 lotIndex, uint64 newUnlockTime) external {
        require(lotIndex < _lots[recipient].length, "lotIndex-oob");

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
        require(lotIndex < _lots[recipient].length, "lotIndex-oob");

        _touchSpend(msg.sender);
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
                // casting to uint128 is safe because MAX_SUPPLY == type(uint128).max
                // forge-lint: disable-next-line(unsafe-typecast)
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
    // Kill switch totale: revoke replaces signing AND migrates funds+lots
    // --------------------------------------------------------------------
    function revokeReplaceSigningAndMigrate(address owner, address newSigning) external {
        _touchSpend(msg.sender);
        require(owner != address(0), "owner=0");
        require(newSigning != address(0), "signingKey=0");

        address rk = registry.revokeKeyOf(owner);
        require(rk != address(0), "not-initialized");
        require(msg.sender == rk, "not-revoke");

        address oldSigning = registry.signingKeyOf(owner);
        require(oldSigning != address(0), "signingKey=0");
        require(oldSigning != newSigning, "same-signing");

        // Update registry (token has REGISTRY_ADMIN_ROLE)
        registry.setSigningKeyFromAdmin(owner, newSigning);

        // Migrate lots (locked + spendable) from oldSigning to newSigning
        Lot[] storage arr = _lots[oldSigning];
        uint256 len = arr.length;

        for (uint256 i = 0; i < len; i++) {
            Lot storage lot = arr[i];
            if (lot.amount == 0) continue;

            _lots[newSigning].push(
                Lot({
                    senderOwner: lot.senderOwner,
                    amount: lot.amount,
                    createdAt: lot.createdAt,
                    minUnlockTime: lot.minUnlockTime,
                    unlockTime: lot.unlockTime,
                    characteristic: lot.characteristic
                })
            );

            lot.amount = 0;
        }

        // oldSigning is now empty; move head to end
        _head[oldSigning] = len;

        // Migrate ERC20 balance
        uint256 bal = balanceOf(oldSigning);
        if (bal > 0) {
            super._transfer(oldSigning, newSigning, bal);
        }
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
        require(!registry.isInitialized(from), "owner-disabled");
        require(!registry.isInitialized(from), "owner-disabled");
        require(block.timestamp <= deadline, "expired");
        require(waitSeconds >= MIN_WAIT_SECONDS, "wait-too-short");

        require(waitSeconds <= MAX_WAIT_SECONDS, "wait-too-long");
        uint256 nonce = registry.signingNonceOf(from);

        bytes32 structHash =
        // forge-lint: disable-next-line(asm-keccak256)
        keccak256(abi.encode(TRANSFER_TYPEHASH, from, to, amount, waitSeconds, characteristic, nonce, deadline));

        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = digest.recover(signature);

        require(signer == from, "bad-signature");

        registry.useSigningNonce(from, nonce);
        _touchSignedOut(_logicalOwnerOf(from));
        _transferWithInheritance(from, to, amount, waitSeconds, characteristic);
    }

    // --------------------------------------------------------------------
    // Internal mechanics
    // --------------------------------------------------------------------

    function _logicalOwnerOf(address a) internal view returns (address) {
        address o = registry.ownerOfSigningKey(a);
        if (o != address(0)) return o;
        return a;
    }

    function _touchSpend(address actor) internal {
        // actor can be signingKey or revokeKey; map to logical owner
        address owner = _logicalOwnerOf(actor);

        _lastSignedOutTs[owner] = uint64(block.timestamp);
    }

    function _touchRenew(address actor) internal {
        address owner = _logicalOwnerOf(actor);
        _lastRenewTs[owner] = uint64(block.timestamp);
    }

    function keepAlive() external {
        _touchRenew(msg.sender);
    }

    function _avgAccumulate(address a) internal {
        if (a == address(0)) return;
        AvgState storage st = _avg[a];
        uint16 yNow = uint256(block.timestamp).yearOf();
        uint64 tNow = uint64(block.timestamp);

        if (st.lastTs == 0) {
            st.year = yNow;
            st.lastTs = tNow;
            st.lastBal = balanceOf(a);
            st.acc = 0;
            return;
        }

        // if year changed, reset bucket (we keep only current-year running average)
        if (st.year != yNow) {
            st.year = yNow;
            st.lastTs = tNow;
            st.lastBal = balanceOf(a);
            st.acc = 0;
            return;
        }

        uint64 dt = tNow - st.lastTs;
        if (dt > 0) {
            st.acc += st.lastBal * uint256(dt);
            st.lastTs = tNow;
        }
    }

    function _avgSetBalance(address a) internal {
        if (a == address(0)) return;
        AvgState storage st = _avg[a];
        uint16 yNow = uint256(block.timestamp).yearOf();
        uint64 tNow = uint64(block.timestamp);

        if (st.lastTs == 0) {
            st.year = yNow;
            st.lastTs = tNow;
            st.lastBal = balanceOf(a);
            st.acc = 0;
            return;
        }

        // if year changed, reset
        if (st.year != yNow) {
            st.year = yNow;
            st.lastTs = tNow;
            st.lastBal = balanceOf(a);
            st.acc = 0;
            return;
        }

        st.lastBal = balanceOf(a);
    }

    function averageBalanceThisYear(address a) external view returns (uint256 avg) {
        AvgState storage st = _avg[a];
        if (st.lastTs == 0) return 0;
        uint16 yNow = uint256(block.timestamp).yearOf();
        if (st.year != yNow) return 0;

        uint256 acc = st.acc;
        uint256 bal = st.lastBal;
        uint64 tNow = uint64(block.timestamp);
        if (tNow > st.lastTs) {
            acc += bal * uint256(tNow - st.lastTs);
        }

        uint256 yearStart = Gregorian.yearStartTs(yNow);
        uint256 elapsed = (block.timestamp >= yearStart) ? (block.timestamp - yearStart) : 0;
        if (elapsed == 0) return 0;

        avg = acc / elapsed;
    }

    // --------------------------------------------------------------------
    // F03: Dead detection helpers
    // --------------------------------------------------------------------

    function _touchSignedOut(address ownerLogical) internal {
        _lastSignedOutTs[ownerLogical] = uint64(block.timestamp);
    }

    function renewLiveness() public {
        address ownerLogical = _logicalOwnerOf(msg.sender);
        _lastRenewTs[ownerLogical] = uint64(block.timestamp);
    }

    /// @dev Shift a timestamp by `deltaYears` calendar years, preserving the offset within the UTC year.
    ///      If the target year is shorter (leap/non-leap), clamp to (yearEndTs-1).
    function _shiftByYears(uint64 baseTs, int16 deltaYears) internal pure returns (uint64) {
        uint16 y = uint256(baseTs).yearOf();

        // Normalize year so that:
        // Gregorian.yearStartTs(y) <= baseTs < Gregorian.yearEndTs(y)
        uint256 start = Gregorian.yearStartTs(y);

        // If yearOf() is approximate (e.g. ignores leap days), baseTs can be < start: fix it
        while (start > uint256(baseTs)) {
            require(y > 1970, "year-oob");
            unchecked {
                y--;
            }

            start = Gregorian.yearStartTs(y);
        }

        uint256 end_ = Gregorian.yearEndTs(y);
        while (uint256(baseTs) >= end_) {
            require(y < type(uint16).max, "year-oob");
            unchecked {
                y++;
            }
            start = end_;
            end_ = Gregorian.yearEndTs(y);
        }

        uint256 offset = uint256(baseTs) - start;

        int256 ty = int256(uint256(y)) + int256(deltaYears);
        int256 maxYear = int256(uint256(type(uint16).max));
        if (ty < 1970) ty = 1970;
        require(ty <= maxYear, "year-oob");

        // forge-lint: disable-next-line(unsafe-typecast)
        // safe: Gregorian year is bounded by conversion logic

        // forge-lint: disable-next-line(unsafe-typecast)

        // safe: Gregorian year is bounded by conversion logic

        // safe: Gregorian year is bounded by conversion logic
        // forge-lint: disable-next-line(unsafe-typecast)
        uint16 targetYear = uint16(uint256(ty));

        uint256 tStart = Gregorian.yearStartTs(targetYear);
        uint256 tEnd = Gregorian.yearEndTs(targetYear);

        // Clamp offset into target year (safe even if year length differs)
        uint256 shifted = tStart + offset;
        if (shifted >= tEnd) shifted = tEnd - 1;

        // forge-lint: disable-next-line(unsafe-typecast) // shifted is derived from timestamp arithmetic bounded by MAX_WAIT_YEARS
        return uint64(shifted);
    }

    function _shiftBackByPolicy(uint64 baseTs, uint256 deltaSeconds) internal pure returns (uint64) {
        // Policy:
        // - if deltaSeconds <= 365 days: pure seconds arithmetic
        // - if deltaSeconds >= 365 days + 1 sec: calendar-based (gregorian nYears) + remainder seconds
        if (deltaSeconds <= 365 days) {
            // casting to uint64 is safe because:
            // - baseTs is a block timestamp (< 2^64 for protocol lifetime)
            // - deltaSeconds is bounded by MAX_WAIT_SECONDS (<= 50*366 days)
            // forge-lint: disable-next-line(unsafe-typecast)
            return uint64(uint256(baseTs) - deltaSeconds);
        }

        uint256 nYears = deltaSeconds / 365 days;
        uint256 rem = deltaSeconds % 365 days;

        // calendar-year shift preserves offset within year; remainder is seconds-based
        // casting to int16 is safe because nYears <= MAX_WAIT_YEARS (50)
        // forge-lint: disable-next-line(unsafe-typecast)
        uint64 shifted = _shiftByYears(baseTs, -int16(int256(nYears)));

        // forge-lint: disable-next-line(unsafe-typecast) // bounded timestamp delta <= MAX_WAIT_SECONDS
        return uint64(uint256(shifted) - rem);
    }

    function _isDead(address ownerLogical) internal view returns (bool) {
        uint64 spend = _lastSignedOutTs[ownerLogical];
        uint64 renew = _lastRenewTs[ownerLogical];

        // Never-seen address is never considered dead (heir admission handled elsewhere)
        if (spend == 0 && renew == 0) return false;

        // If the chain time is within the first INACTIVITY_YEARS since 1970,
        // nobody can be considered inactive "by years" yet.
        uint16 nowYear = uint256(block.timestamp).yearOf();
        if (nowYear < uint16(1970 + INACTIVITY_YEARS)) return false;

        // Calendar-year cutoff: "now minus INACTIVITY_YEARS" preserving offset within year
        // forge-lint: disable-next-line(unsafe-typecast) // INACTIVITY_YEARS = 7 fits safely in int16
        uint64 cutoff = _shiftByYears(uint64(block.timestamp), -int16(INACTIVITY_YEARS));

        bool spendExpired = (spend == 0) ? true : spend < cutoff;
        bool renewExpired = (renew == 0) ? true : renew < cutoff;

        return spendExpired && renewExpired;
    }

    function _isDeadStrict(address ownerLogical) internal view returns (bool) {
        uint64 spend = _lastSignedOutTs[ownerLogical];
        uint64 renew = _lastRenewTs[ownerLogical];

        // Never-seen => treat as dead (STRICT)
        if (spend == 0 && renew == 0) return true;

        uint64 cutoff = _shiftBackByPolicy(uint64(block.timestamp), uint256(DEAD_AFTER_SECONDS));

        bool spendExpired = (spend == 0) ? true : spend < cutoff;
        bool renewExpired = (renew == 0) ? true : renew < cutoff;

        return spendExpired && renewExpired;
    }

    function _transferWithInheritance(
        address sender,
        address recipient,
        uint256 amount,
        uint64 waitSeconds,
        bytes32 characteristic
    ) internal {
        // block transfers to dead recipients (recipient is the heir of this transfer)
        address recipOwner = _logicalOwnerOf(recipient);
        if (_isDead(recipOwner)) revert RecipientDead();
        recipient = _resolveRecipient(recipient);

        // Resolve logical owner (if sender is signingKey)
        address ownerLogical = registry.ownerOfSigningKey(sender);
        if (ownerLogical == address(0)) ownerLogical = sender;

        require(waitSeconds >= MIN_WAIT_SECONDS, "wait-too-short");

        _consumeSpendableLots(sender, amount);

        uint64 nowTs = uint64(block.timestamp);
        uint64 minUnlock = nowTs + MIN_WAIT_SECONDS;

        uint64 unlockAt = nowTs + waitSeconds;

        _lots[recipient].push(
            Lot({
                senderOwner: ownerLogical,
                // casting to uint128 is safe because MAX_SUPPLY == type(uint128).max
                // forge-lint: disable-next-line(unsafe-typecast)
                amount: uint128(amount),
                createdAt: nowTs,
                minUnlockTime: minUnlock,
                unlockTime: unlockAt,
                characteristic: characteristic
            })
        );

        uint256 lotIndex = _lots[recipient].length - 1;
        super._transfer(sender, recipient, amount);

        emit TransferWithInheritance(sender, recipient, amount, unlockAt, minUnlock, characteristic, lotIndex);
    }

    function _consumeSpendableLots(address owner, uint256 amount) internal {
        Lot[] storage arr = _lots[owner];
        uint256 remaining = amount;
        uint64 nowTs = uint64(block.timestamp);

        uint256 h = _head[owner];
        uint256 len = arr.length;
        uint256 i = h;

        for (; i < len && remaining != 0; ++i) {
            Lot storage lot = arr[i];
            uint128 amt = lot.amount;
            if (amt == 0) continue;
            if (lot.unlockTime > nowTs) continue;

            if (amt <= remaining) {
                remaining -= amt;
                lot.amount = 0;
            } else {
                // forge-lint: disable-next-line(unsafe-typecast)
                lot.amount = uint128(uint256(amt) - remaining);
                remaining = 0;
            }
        }

        // F02A GC trigger: compact only when head moved far enough to matter.
        // - avoid doing it for small arrays
        // - do it when head > 64 and head is past half of the array
        {
            uint256 hGc = _head[owner];
            uint256 lenGc = arr.length;
            if (hGc > 64 && (hGc * 2) > lenGc) {
                _compactLots(owner);
            }
        }

        require(remaining == 0, "insufficient-spendable");

        while (h < len && arr[h].amount == 0) {
            ++h;
        }
        _head[owner] = h;
    }

    // --------------------------------------------------------------------
    // F02A: automatic lot compaction (GC) to cap long-term scan costs.
    // Triggered only when head has moved far into the array.
    // --------------------------------------------------------------------
    function _compactLots(address owner) internal {
        Lot[] storage arr = _lots[owner];
        uint256 h = _head[owner];
        uint256 len = arr.length;
        if (h == 0 || h >= len) {
            _head[owner] = (h >= len) ? len : h;
            return;
        }

        // Move live tail to the front: arr[i] = arr[i + h]
        uint256 newLen = len - h;
        for (uint256 i = 0; i < newLen; ++i) {
            arr[i] = arr[i + h];
        }

        // Pop extra slots
        for (uint256 i = len; i > newLen; --i) {
            arr.pop();
        }

        _head[owner] = 0;
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        to = _resolveRecipient(to);
        require(totalSupply() + amount <= MAX_SUPPLY, "cap exceeded");
        uint64 nowTs = uint64(block.timestamp);

        _lots[to].push(
            Lot({
                senderOwner: address(0),
                // casting to uint128 is safe because MAX_SUPPLY == type(uint128).max
                // forge-lint: disable-next-line(unsafe-typecast)
                amount: uint128(amount),
                createdAt: nowTs,
                minUnlockTime: nowTs,
                unlockTime: nowTs,
                characteristic: bytes32(0)
            })
        );

        _mint(to, amount);
    }

    // --------------------------------------------------------------------
    // Central hook for ALL ERC20 balance moves (transfer/mint/burn)
    // If someone sends/mints to an initialized owner address, redirect to signingKey.
    // --------------------------------------------------------------------

    // --------------------------------------------------------------------
    // Gregorian year calculation (UTC)

    // --------------------------------------------------------------------
    function _currentYear() internal view returns (uint16) {
        // Unix timestamp -> Gregorian year approximation
        // 1970-01-01 is year 1970
        uint256 z = block.timestamp / 1 days + 719468;
        uint256 era = (z >= 0 ? z : z - 146096) / 146097;
        uint256 doe = z - era * 146097; // [0, 146096]
        uint256 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365; // [0,399]
        uint256 y = yoe + era * 400;
        // casting to uint16 is safe: Gregorian year will never approach uint16 max in any realistic chain lifetime
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint16(y);
    }
}
