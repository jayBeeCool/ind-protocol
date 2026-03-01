// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {InheritanceDollar} from "contracts/InheritanceDollar.sol";
import {InheritanceDollarCompat} from "contracts/InheritanceDollarCompat.sol";
import {INDKeyRegistry} from "contracts/INDKeyRegistry.sol";

contract DeployIND is Script {
    function run() external {
        vm.startBroadcast();

        INDKeyRegistry registry = new INDKeyRegistry(msg.sender);

        InheritanceDollar core = new InheritanceDollar(
            msg.sender, // admin
            registry // INDKeyRegistry (NOT address)
        );

        InheritanceDollarCompat compat = new InheritanceDollarCompat(
            address(core),
            registry // INDKeyRegistry (NOT address)
        );

        // silence unused var warning (optional)
        compat;

        vm.stopBroadcast();
    }
}
