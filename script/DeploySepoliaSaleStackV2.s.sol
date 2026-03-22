// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {INDSale} from "contracts/INDSale.sol";
import {INDOpenDepositReceiver} from "contracts/INDOpenDepositReceiver.sol";
import {INDDepositReceiver} from "contracts/INDDepositReceiver.sol";

contract DeploySepoliaSaleStackV2 is Script {
    function run() external {
        address admin = vm.envAddress("SAFE_ADMIN");
        address vault = vm.envAddress("VAULT_PROXY");
        address recipient = vm.envAddress("DEPOSIT_RECIPIENT");

        vm.startBroadcast();

        INDSale sale = new INDSale(admin, vault);
        INDOpenDepositReceiver openReceiver = new INDOpenDepositReceiver(address(sale));
        INDDepositReceiver depositReceiver = new INDDepositReceiver(address(sale), recipient);

        vm.stopBroadcast();

        console2.log("SALE=", address(sale));
        console2.log("OPEN_DEPOSIT_RECEIVER=", address(openReceiver));
        console2.log("DEPOSIT_RECEIVER=", address(depositReceiver));
    }
}
