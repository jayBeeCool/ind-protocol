// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {INDKeyRegistry} from "contracts/INDKeyRegistry.sol";
import {InheritanceDollarVaultUpgradeable} from "contracts/InheritanceDollarVaultUpgradeable.sol";
import {INDSale} from "contracts/INDSale.sol";

contract DeployMainnetVaultStack is Script {
    function run() external {
        require(block.chainid == 1, "NOT_MAINNET");

        address deployer = vm.envAddress("MAINNET_DEPLOYER");

        address safe = vm.envAddress("SAFE_MAINNET");
        uint256 maxSupply = vm.envUint("MAX_SUPPLY");
        uint256 genesisAmount = vm.envUint("GENESIS_AMOUNT");

        require(safe != address(0), "SAFE_ZERO");
        require(maxSupply >= genesisAmount, "MAX_LT_GENESIS");

        vm.startBroadcast(deployer);

        INDKeyRegistry registry = new INDKeyRegistry(deployer);

        InheritanceDollarVaultUpgradeable implementation =
            new InheritanceDollarVaultUpgradeable();

        bytes memory initData =
            abi.encodeCall(
                InheritanceDollarVaultUpgradeable.initialize,
                (deployer, maxSupply, address(registry))
            );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        InheritanceDollarVaultUpgradeable vault =
            InheritanceDollarVaultUpgradeable(address(proxy));

        INDSale sale = new INDSale(deployer, address(vault));

        bytes32 REGISTRY_ADMIN_ROLE = registry.REGISTRY_ADMIN_ROLE();

        bytes32 VAULT_DEFAULT_ADMIN_ROLE = vault.DEFAULT_ADMIN_ROLE();
        bytes32 VAULT_UPGRADER_ROLE = vault.UPGRADER_ROLE();
        bytes32 VAULT_MINTER_ROLE = vault.MINTER_ROLE();

        bytes32 SALE_DEFAULT_ADMIN_ROLE = sale.DEFAULT_ADMIN_ROLE();
        bytes32 SALE_ADMIN_ROLE = sale.ADMIN_ROLE();

        registry.grantRole(REGISTRY_ADMIN_ROLE, address(vault));
        registry.grantRole(REGISTRY_ADMIN_ROLE, safe);
        registry.grantRole(registry.DEFAULT_ADMIN_ROLE(), safe);

        vault.grantRole(VAULT_MINTER_ROLE, address(sale));
        vault.grantRole(VAULT_DEFAULT_ADMIN_ROLE, safe);
        vault.grantRole(VAULT_UPGRADER_ROLE, safe);
        vault.grantRole(VAULT_MINTER_ROLE, safe);

        sale.grantRole(SALE_DEFAULT_ADMIN_ROLE, safe);
        sale.grantRole(SALE_ADMIN_ROLE, safe);

        vault.mint(safe, genesisAmount);

        registry.revokeRole(REGISTRY_ADMIN_ROLE, deployer);
        registry.revokeRole(registry.DEFAULT_ADMIN_ROLE(), deployer);

        vault.revokeRole(VAULT_UPGRADER_ROLE, deployer);
        vault.revokeRole(VAULT_MINTER_ROLE, deployer);
        vault.revokeRole(VAULT_DEFAULT_ADMIN_ROLE, deployer);

        sale.revokeRole(SALE_ADMIN_ROLE, deployer);
        sale.revokeRole(SALE_DEFAULT_ADMIN_ROLE, deployer);

        vm.stopBroadcast();

        console2.log("DEPLOYER=", deployer);
        console2.log("SAFE=", safe);
        console2.log("REGISTRY=", address(registry));
        console2.log("IMPLEMENTATION=", address(implementation));
        console2.log("VAULT_PROXY=", address(proxy));
        console2.log("SALE=", address(sale));
        console2.log("GENESIS_AMOUNT=", genesisAmount);
    }
}
