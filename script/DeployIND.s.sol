// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "contracts/InheritanceDollar.sol";
import "contracts/InheritanceDollarCompat.sol";

contract DeployIND is Script {
    function run() external {
        vm.startBroadcast();

        // NOTE: adjust constructor args if your contracts require them.
        // If InheritanceDollar has no constructor args, keep as-is.
        InheritanceDollar core = new InheritanceDollar();

        // If Compat wraps an existing core, adjust accordingly.
        // If Compat has a different constructor, update here.
        InheritanceDollarCompat compat = new InheritanceDollarCompat(address(core));

        console2.log("InheritanceDollar:", address(core));
        console2.log("InheritanceDollarCompat:", address(compat));

        vm.stopBroadcast();
    }
}
