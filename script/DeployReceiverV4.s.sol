// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {INDReceiverV4} from "../contracts/INDReceiverV4.sol";

contract DeployReceiverV4 is Script {
    address constant SALE = 0x94D7b88Fea52C8Cafd27f93D9E99CA5Fd3362e22;

    function run() external {
        vm.startBroadcast();
        new INDReceiverV4(SALE);
        vm.stopBroadcast();
    }
}
