// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./InheritanceDollar.sol";

// Thin wrapper used only for legacy test compatibility.
// It inherits everything from InheritanceDollar.
// DO NOT override anything.
contract InheritanceDollarCompat is InheritanceDollar {
    constructor(address admin, INDKeyRegistry keyRegistry) InheritanceDollar(admin, keyRegistry) {}
}
