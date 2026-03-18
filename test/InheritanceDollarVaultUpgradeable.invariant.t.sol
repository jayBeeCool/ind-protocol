// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../contracts/InheritanceDollarVaultUpgradeable.sol";
import "./mocks/MockINDKeyRegistryLite.sol";

contract InheritanceDollarVaultUpgradeableInvariantTest is Test {
    InheritanceDollarVaultUpgradeable internal ind;
    MockINDKeyRegistryLite internal reg;

    address internal admin = address(0xA11CE);
    address internal sale = address(0x5A1E);
    address internal a = address(0x1001);
    address internal b = address(0x1002);
    address internal c = address(0x1003);

    uint256 internal constant MAX_SUPPLY = 100_000_000_000 ether;

    function setUp() external {
        reg = new MockINDKeyRegistryLite();
        InheritanceDollarVaultUpgradeable impl = new InheritanceDollarVaultUpgradeable();

        bytes memory initData =
            abi.encodeCall(InheritanceDollarVaultUpgradeable.initialize, (admin, MAX_SUPPLY, address(reg)));

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        ind = InheritanceDollarVaultUpgradeable(address(proxy));

        vm.startPrank(admin);
        ind.grantRole(ind.MINTER_ROLE(), sale);
        vm.stopPrank();

        vm.startPrank(sale);
        ind.mint(a, 100 ether);
        ind.mint(b, 200 ether);
        ind.mint(c, 300 ether);
        vm.stopPrank();
    }

    function invariant_sum_of_known_balances_matches_total_supply() external view {
        uint256 sum = ind.balanceOf(a) + ind.balanceOf(b) + ind.balanceOf(c) + ind.protectedBalanceOf(a)
            + ind.protectedBalanceOf(b) + ind.protectedBalanceOf(c);

        assertEq(sum, ind.totalSupply());
    }
}
