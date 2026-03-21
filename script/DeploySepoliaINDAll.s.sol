// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// forge-lint: disable-next-line(unaliased-plain-import)
import "forge-std/Script.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../contracts/INDKeyRegistry.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../contracts/InheritanceDollar.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../contracts/INDSale.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../contracts/INDDepositReceiver.sol";

contract DeploySepoliaINDAll is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(pk);
        address recipient = vm.envAddress("RECIPIENT_ADDRESS");

        vm.startBroadcast();

        INDKeyRegistry registry = new INDKeyRegistry(admin);
        InheritanceDollar ind = new InheritanceDollar(admin, registry);
        INDSale sale = new INDSale(admin, address(ind));
        INDDepositReceiver receiver = new INDDepositReceiver(address(sale), recipient);

        // forge-lint: disable-next-line(mixed-case-variable)
        bytes32 REGISTRY_ADMIN_ROLE = registry.REGISTRY_ADMIN_ROLE();
        // forge-lint: disable-next-line(mixed-case-variable)
        registry.grantRole(REGISTRY_ADMIN_ROLE, address(ind));

        // forge-lint: disable-next-line(mixed-case-variable)
        bytes32 MINTER_ROLE = ind.MINTER_ROLE();
        // forge-lint: disable-next-line(mixed-case-variable)
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
