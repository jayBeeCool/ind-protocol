// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract INDKeyRegistry is AccessControl {
    bytes32 public constant REGISTRY_ADMIN_ROLE = keccak256("REGISTRY_ADMIN_ROLE");

    struct Keys {
        address signingKey; // hot key (transfers)
        address revokeKey; // cold key (reduce/revoke)
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

    function ownerOfRevokeKey(address revokeKey) external view returns (address) {
        return _ownerOfRevoke[revokeKey];
    }

    // -------- Initialization --------

    function initKeys(address signingKey, address revokeKey) internal {
        require(signingKey != address(0), "signingKey=0");
        require(revokeKey != address(0), "revokeKey=0");
        require(signingKey != revokeKey, "keys-equal");
        require(_ownerOfSigning[signingKey] == address(0), "signingKey-in-use");
        require(_ownerOfRevoke[revokeKey] == address(0), "revokeKey-in-use");

        Keys storage k = _keys[msg.sender];
        require(!k.initialized, "already-initialized");

        k.signingKey = signingKey;
        k.revokeKey = revokeKey;
        k.signingNonce = 0;
        k.revokeNonce = 0;
        k.initialized = true;

        _ownerOfSigning[signingKey] = msg.sender;
        _ownerOfRevoke[revokeKey] = msg.sender;

        emit KeysInitialized(msg.sender, signingKey, revokeKey);
    }

    // -------- Rotations (B1+B) --------

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

    // -------- Admin helpers (called by token after signature verification) --------

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

    function setSigningKeyFromAdmin(address owner, address newKey) external onlyRole(REGISTRY_ADMIN_ROLE) {
        require(newKey != address(0), "signingKey=0");
        require(_ownerOfSigning[newKey] == address(0), "signingKey-in-use");
        Keys storage k = _keys[owner];
        require(k.initialized, "not-initialized");
        address old = k.signingKey;

        delete _ownerOfSigning[old];
        _ownerOfSigning[newKey] = owner;

        k.signingKey = newKey;
        emit SigningKeyRotated(owner, old, newKey, k.revokeNonce);
    }

    function setRevokeKeyFromAdmin(address owner, address newKey) external onlyRole(REGISTRY_ADMIN_ROLE) {
        require(newKey != address(0), "revokeKey=0");
        require(_ownerOfRevoke[newKey] == address(0), "revokeKey-in-use");
        Keys storage k = _keys[owner];
        require(k.initialized, "not-initialized");
        address old = k.revokeKey;

        delete _ownerOfRevoke[old];
        _ownerOfRevoke[newKey] = owner;

        k.revokeKey = newKey;
        emit RevokeKeyRotated(owner, old, newKey, k.revokeNonce);
    }
}
