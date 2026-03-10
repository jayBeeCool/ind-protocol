// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/INDReceiverV3.sol";

contract DeployReceiverV3 is Script {
    address constant SALE = 0x94D7b88Fea52C8Cafd27f93D9E99CA5Fd3362e22;

    function run() external {
        vm.startBroadcast();
        INDReceiverV3 receiver = new INDReceiverV3(SALE);
        vm.stopBroadcast();
        console2.log("RECEIVER_V3:", address(receiver));
    }
}
