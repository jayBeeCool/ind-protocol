// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {INDKeyRegistry} from "contracts/INDKeyRegistry.sol";
import {InheritanceDollarVaultUpgradeable} from "contracts/InheritanceDollarVaultUpgradeable.sol";

contract DeploySepoliaVaultStackV2 is Script {
    function run() external {
        address admin = vm.envAddress("SAFE_ADMIN");
        uint256 maxSupply = vm.envUint("MAX_SUPPLY");

        vm.startBroadcast();

        INDKeyRegistry registry = new INDKeyRegistry(admin);
        InheritanceDollarVaultUpgradeable implementation = new InheritanceDollarVaultUpgradeable();

        bytes memory initData = abi.encodeCall(
            InheritanceDollarVaultUpgradeable.initialize,
            (admin, maxSupply, address(registry))
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        vm.stopBroadcast();

        console2.log("REGISTRY=", address(registry));
        console2.log("IMPLEMENTATION=", address(implementation));
        console2.log("VAULT_PROXY=", address(proxy));
    }
}
