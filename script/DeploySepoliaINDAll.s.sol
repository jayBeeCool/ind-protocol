// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/INDKeyRegistry.sol";
import "../contracts/InheritanceDollar.sol";
import "../contracts/INDSale.sol";
import "../contracts/INDDepositReceiver.sol";

contract DeploySepoliaINDAll is Script {
    function run() external {
        address admin = vm.addr(pk);
        address recipient = vm.envAddress("RECIPIENT_ADDRESS");

        vm.startBroadcast();

        INDKeyRegistry registry = new INDKeyRegistry(admin);
        InheritanceDollar ind = new InheritanceDollar(admin, registry);
        INDSale sale = new INDSale(admin, address(ind));
        INDDepositReceiver receiver = new INDDepositReceiver(address(sale), recipient);

        bytes32 REGISTRY_ADMIN_ROLE = registry.REGISTRY_ADMIN_ROLE();
        registry.grantRole(REGISTRY_ADMIN_ROLE, address(ind));

        bytes32 MINTER_ROLE = ind.MINTER_ROLE();
        ind.grantRole(MINTER_ROLE, address(sale));

        vm.stopBroadcast();

        console2.log("ADMIN    :", admin);
        console2.log("RECIPIENT:", recipient);
        console2.log("REGISTRY :", address(registry));
        console2.log("IND      :", address(ind));
        console2.log("SALE     :", address(sale));
        console2.log("RECEIVER :", address(receiver));
    }
}
