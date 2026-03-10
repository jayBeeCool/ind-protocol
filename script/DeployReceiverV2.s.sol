// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/INDReceiverV2.sol";

contract DeployReceiverV2 is Script {
    function run() external returns (INDReceiverV2 receiver) {
        address sale = vm.envAddress("IND_SALE");
        vm.startBroadcast();
        receiver = new INDReceiverV2(sale);
        vm.stopBroadcast();
    }
}
