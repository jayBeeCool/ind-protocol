// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../contracts/interfaces/IINDKeyRegistryLite.sol";

contract MockINDKeyRegistryLite is IINDKeyRegistryLite {
    mapping(address => bool) private _initialized;
    mapping(address => address) private _ownerOfSigning;
    mapping(address => address) private _signingOfOwner;
    mapping(address => address) private _revokeOfOwner;

    function setOwnerKeys(address owner, address signingKey) external {
        _initialized[owner] = true;
        _signingOfOwner[owner] = signingKey;
        _revokeOfOwner[owner] = address(0);
        if (signingKey != address(0)) {
            _ownerOfSigning[signingKey] = owner;
        }
    }

    function setOwnerKeys(address owner, address signingKey, address revokeKey) external {
        _initialized[owner] = true;
        _signingOfOwner[owner] = signingKey;
        _revokeOfOwner[owner] = revokeKey;
        if (signingKey != address(0)) {
            _ownerOfSigning[signingKey] = owner;
        }
    }

    function clearOwner(address owner) external {
        address sk = _signingOfOwner[owner];
        _initialized[owner] = false;
        _signingOfOwner[owner] = address(0);
        _revokeOfOwner[owner] = address(0);
        if (sk != address(0)) {
            _ownerOfSigning[sk] = address(0);
        }
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
