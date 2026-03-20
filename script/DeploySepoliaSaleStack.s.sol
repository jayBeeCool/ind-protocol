// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/InheritanceDollar.sol";
import "../contracts/INDSale.sol";
import "../contracts/INDOpenDepositReceiver.sol";

contract DeploySepoliaSaleStack is Script {
    // vecchio IND Sepolia con 10B già mintati
    address constant IND_ADDR = 0xC9A8F1017665D64A7E809886b7Df51dc232d3051;

    // vero admin/minter del vecchio stack
    address constant SAFE_ADMIN = 0x0527A7671b4B05f20678b8D93EF072c15F6E4aF9;

    function run() external {
        vm.startBroadcast();

        InheritanceDollar ind = InheritanceDollar(IND_ADDR);
        INDSale sale = new INDSale(SAFE_ADMIN, address(ind));
        INDOpenDepositReceiver receiver = new INDOpenDepositReceiver(address(sale));

        vm.stopBroadcast();

        console2.log("IND      :", address(ind));
        console2.log("SAFE     :", SAFE_ADMIN);
        console2.log("SALE     :", address(sale));
        console2.log("RECEIVER :", address(receiver));
    }
}
