// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {INDReceiverV3} from "../contracts/INDReceiverV3.sol";

contract DeployReceiverV3 is Script {
    address constant SALE = 0x94D7b88Fea52C8Cafd27f93D9E99CA5Fd3362e22;

    function run() external {
        vm.startBroadcast();
        INDReceiverV3 receiver = new INDReceiverV3(SALE);
        vm.stopBroadcast();
        console2.log("RECEIVER_V3:", address(receiver));
    }
}
