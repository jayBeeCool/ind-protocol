// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../contracts/InheritanceDollarVaultUpgradeable.sol";
import "./mocks/MockINDKeyRegistryLite.sol";

contract YearBoundaryTest is Test {
    InheritanceDollarVaultUpgradeable ind;
    MockINDKeyRegistryLite reg;

    address admin = address(0xA11CE);
    address sale = address(0x5A1E);
    uint256 ownerPk = 0xA11CE55;
    address owner;

    uint256 constant MAX_SUPPLY = 100_000_000_000 ether;

    function setUp() external {
        owner = vm.addr(ownerPk);

        reg = new MockINDKeyRegistryLite();
        InheritanceDollarVaultUpgradeable impl = new InheritanceDollarVaultUpgradeable();

        bytes memory initData =
            abi.encodeCall(InheritanceDollarVaultUpgradeable.initialize, (admin, MAX_SUPPLY, address(reg)));

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        ind = InheritanceDollarVaultUpgradeable(address(proxy));

        vm.startPrank(admin);
        ind.grantRole(ind.MINTER_ROLE(), sale);
        vm.stopPrank();

        vm.prank(sale);
        ind.mint(owner, 100 ether);
    }

    function test_average_resets_correctly_on_year_change() external {
        // Vai a 31 dicembre (fine anno)
        uint256 year = 2025;
        uint256 dec31 = Gregorian.yearEndTs(uint16(year)) - 1;
        vm.warp(dec31 - 10 days);

        // interazione prima del cambio anno
        vm.prank(owner);
        ind.protect(50 ether);

        // attraversa il nuovo anno
        vm.warp(dec31 + 1 days);

        // nuova interazione → deve resettare avg
        vm.prank(owner);
        ind.keepAlive();

        uint256 avg = ind.averageBalanceThisYear(owner);

        // appena iniziato l’anno → media ≈ saldo attuale
        assertGt(avg, 99 ether);
        assertLt(avg, 101 ether);
    }
}
