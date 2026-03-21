// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IINDKeyRegistryLite} from "../../contracts/interfaces/IINDKeyRegistryLite.sol";

contract MockINDKeyRegistryLite is IINDKeyRegistryLite {
    mapping(address => bool) private _initialized;
    mapping(address => address) private _ownerOfSigning;
    mapping(address => address) private _signingOfOwner;
    mapping(address => address) private _revokeOfOwner;

    function setOwnerKeys(address owner, address signingKey, address revokeKey) external {
        if (_signingOfOwner[owner] != address(0)) {
            _ownerOfSigning[_signingOfOwner[owner]] = address(0);
        }
        _initialized[owner] = true;
        _signingOfOwner[owner] = signingKey;
        _revokeOfOwner[owner] = revokeKey;
        if (signingKey != address(0)) _ownerOfSigning[signingKey] = owner;
    }

    function setOwnerKeys(address owner, address signingKey) external {
        if (_signingOfOwner[owner] != address(0)) {
            _ownerOfSigning[_signingOfOwner[owner]] = address(0);
        }
        _initialized[owner] = true;
        _signingOfOwner[owner] = signingKey;
        if (signingKey != address(0)) _ownerOfSigning[signingKey] = owner;
    }

    function clearOwner(address owner) external {
        address sk = _signingOfOwner[owner];
        _initialized[owner] = false;
        _signingOfOwner[owner] = address(0);
        _revokeOfOwner[owner] = address(0);
        if (sk != address(0)) _ownerOfSigning[sk] = address(0);
    }

    function initKeysFromAdmin(address owner, address signingKey, address revokeKey) external override {
        if (_signingOfOwner[owner] != address(0)) {
            _ownerOfSigning[_signingOfOwner[owner]] = address(0);
        }
        _initialized[owner] = true;
        _signingOfOwner[owner] = signingKey;
        _revokeOfOwner[owner] = revokeKey;
        if (signingKey != address(0)) _ownerOfSigning[signingKey] = owner;
    }

    function rotateSigningKeyFromRevoke(address owner, address newSigningKey) external override {
        address oldSigning = _signingOfOwner[owner];
        if (oldSigning != address(0)) _ownerOfSigning[oldSigning] = address(0);
        _signingOfOwner[owner] = newSigningKey;
        if (newSigningKey != address(0)) _ownerOfSigning[newSigningKey] = owner;
    }

    function isInitialized(address owner) external view override returns (bool) {
        return _initialized[owner];
    }

    function ownerOfSigningKey(address signingKey) external view override returns (address) {
        return _ownerOfSigning[signingKey];
    }

    function signingKeyOf(address owner) external view override returns (address) {
        return _signingOfOwner[owner];
    }

    function revokeKeyOf(address owner) external view override returns (address) {
        return _revokeOfOwner[owner];
    }
}
