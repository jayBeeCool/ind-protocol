// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/INDReceiverV4.sol";

contract DeployReceiverV4 is Script {
    address constant SALE = 0x94D7b88Fea52C8Cafd27f93D9E99CA5Fd3362e22;

    function run() external {
        vm.startBroadcast();
        INDReceiverV4 receiver = new INDReceiverV4(SALE);
        vm.stopBroadcast();
        console2.log("RECEIVER_V4:", address(receiver));
    }
}
