// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "./interfaces/IINDKeyRegistryLite.sol";

contract InheritanceDollarVaultUpgradeable is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    IERC20,
    IERC20Metadata
{
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint64 public constant MIN_INHERITANCE_WAIT = 1 days;
    uint64 public constant MAX_INHERITANCE_WAIT = uint64(50 * 365 days);
    uint64 public constant DEAD_AFTER = uint64(7 * 365 days);

    struct Lot {
        uint256 amount;
        uint64 unlockTime;
        uint64 minUnlockTime;
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
    mapping(address => uint64) private _lastInteraction;

    event TransferWithInheritance(
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        uint64 unlockTime,
        uint64 minUnlockTime,
        bytes32 characteristic,
        uint256 lotIndex
    );

    error ZeroAddress();
    error ZeroAmount();
    error MaxSupplyExceeded();
    error InsufficientUnprotectedBalance();
    error InsufficientProtectedBalance();
    error InsufficientAllowance();
    error InheritanceWaitTooShort();
    error InheritanceWaitTooLong();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, uint256 maxSupply_, address registry_) external initializer {
        if (admin == address(0)) revert ZeroAddress();
        if (registry_ == address(0)) revert ZeroAddress();

        __AccessControl_init();

        _nameCustom = "Inheritance Dollar";
        _symbolCustom = "IND";
        maxSupply = maxSupply_;
        registry = IINDKeyRegistryLite(registry_);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);

        _touchInteraction(admin);
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

    function lastInteractionOf(address account) external view returns (uint64) {
        return _lastInteraction[account];
    }

    function isDead(address account) public view returns (bool) {
        uint64 li = _lastInteraction[account];
        if (li == 0) return false;
        return uint64(block.timestamp) > li + DEAD_AFTER;
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

    function totalUserBalanceOf(address user) external view returns (uint256) {
        return _unprotectedBalances[user] + protectedBalanceOf(user);
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        address owner = msg.sender;
        if (registry.isInitialized(owner)) _revertOwnerDisabled();

        _allowances[owner][spender] = amount;
        _touchInteraction(owner);
        emit Approval(owner, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        address sender = msg.sender;
        if (registry.isInitialized(sender)) _revertOwnerDisabled();

        address resolved = _resolveRecipient(to);
        _transferUnprotected(sender, resolved, amount);
        _touchInteraction(sender);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        if (registry.isInitialized(from)) _revertOwnerDisabled();

        uint256 a = _allowances[from][msg.sender];
        if (a < amount) revert InsufficientAllowance();

        unchecked {
            _allowances[from][msg.sender] = a - amount;
        }
        emit Approval(from, msg.sender, _allowances[from][msg.sender]);

        address resolved = _resolveRecipient(to);
        _transferUnprotected(from, resolved, amount);
        _touchInteraction(from);
        return true;
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (_totalSupplyCustom + amount > maxSupply) revert MaxSupplyExceeded();

        address resolved = _resolveRecipient(to);

        _totalSupplyCustom += amount;
        _unprotectedBalances[resolved] += amount;

        emit Transfer(address(0), resolved, amount);
    }

    function protect(uint256 amount) external returns (bool) {
        if (amount == 0) revert ZeroAmount();

        address sender = msg.sender;
        if (registry.isInitialized(sender)) _revertOwnerDisabled();
        if (_unprotectedBalances[sender] < amount) revert InsufficientUnprotectedBalance();

        _unprotectedBalances[sender] -= amount;

        _lots[sender].push(
            Lot({amount: amount, unlockTime: uint64(block.timestamp), minUnlockTime: uint64(block.timestamp)})
        );

        _touchInteraction(sender);
        return true;
    }

    function unprotect(uint256 amount) external returns (bool) {
        if (amount == 0) revert ZeroAmount();

        address sender = msg.sender;
        if (registry.isInitialized(sender)) _revertOwnerDisabled();

        _consumeSpendableLots(sender, amount);
        _unprotectedBalances[sender] += amount;

        _touchInteraction(sender);
        return true;
    }

    function transferWithInheritance(address to, uint256 amount, uint64 waitSeconds, bytes32 characteristic)
        external
        returns (bool)
    {
        if (waitSeconds < MIN_INHERITANCE_WAIT) revert InheritanceWaitTooShort();
        if (waitSeconds > MAX_INHERITANCE_WAIT) revert InheritanceWaitTooLong();

        address sender = msg.sender;
        if (registry.isInitialized(sender)) _revertOwnerDisabled();

        address resolved = _resolveRecipient(to);
        _consumeSpendableLots(sender, amount);
        _touchInteraction(sender);

        uint64 unlockTime = uint64(block.timestamp) + waitSeconds;

        _lots[resolved].push(Lot({amount: amount, unlockTime: unlockTime, minUnlockTime: unlockTime}));

        emit TransferWithInheritance(
            sender, resolved, amount, unlockTime, unlockTime, characteristic, _lots[resolved].length - 1
        );

        return true;
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
                delete l[i];
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

    function _resolveRecipient(address to) internal view returns (address) {
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

    function _touchInteraction(address actor) internal {
        address owner = _logicalOwnerOf(actor);
        _lastInteraction[owner] = uint64(block.timestamp);
    }

    uint256[50] private __gap;
}
