// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./InheritanceDollar.sol";

/*
    Compat layer SOLO per esporre firme legacy.
    Nessuna logica qui.
    Non chiama funzioni interne del core.
*/

contract InheritanceDollarCompat is InheritanceDollar {

    constructor(address admin, INDKeyRegistry keyRegistry)
        InheritanceDollar(admin, keyRegistry) {}

    // ---- Legacy API stubs (verranno implementate nello Step B) ----

    function activateKeysAndMigrate(address, address) external pure {
        revert("B:activateKeysAndMigrate");
    }

    function transferWithInheritance_legacy(
        address,
        uint256,
        uint64,
        bytes32
    ) external pure returns (bool) {
        revert("B:transferWithInheritance");
    }

    function reduceUnlockTimeBySig(
        address,
        address,
        uint256,
        uint64,
        uint256,
        bytes calldata
    ) external pure {
        revert("B:reduceUnlockTimeBySig");
    }

    function revokeBySig(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure {
        revert("B:revokeBySig");
    }
}
