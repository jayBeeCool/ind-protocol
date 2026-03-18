// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IINDKeyRegistryLite {
    function isInitialized(address owner) external view returns (bool);
    function ownerOfSigningKey(address signingKey) external view returns (address);
    function signingKeyOf(address owner) external view returns (address);
    function revokeKeyOf(address owner) external view returns (address);
}
