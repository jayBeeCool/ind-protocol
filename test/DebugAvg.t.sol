// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../contracts/InheritanceDollarVaultUpgradeable.sol";
import "./mocks/MockINDKeyRegistryLite.sol";

contract DebugAvgTest is Test {
    InheritanceDollarVaultUpgradeable internal ind;
    MockINDKeyRegistryLite internal reg;

    uint256 internal ownerPk = 0xA11CE55;
    address internal owner;
    address internal admin = address(0xA11CE);
    address internal sale = address(0x5A1E);

    uint256 internal constant MAX_SUPPLY = 100_000_000_000 ether;

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

    function test_debug_avg_path() external {
        (uint16 y1, uint64 t1, uint256 a1, uint256 b1, address o1, address p1, uint256 tot1) = ind.debugAvg(owner);
        emit log_named_uint("year after mint", y1);
        emit log_named_uint("lastTs after mint", t1);
        emit log_named_uint("acc after mint", a1);
        emit log_named_uint("lastBal after mint", b1);
        emit log_named_address("ownerLogical after mint", o1);
        emit log_named_address("primary after mint", p1);
        emit log_named_uint("totalNow after mint", tot1);

        vm.warp(block.timestamp + 10 days);
        vm.prank(owner);
        ind.protect(40 ether);

        (uint16 y2, uint64 t2, uint256 a2, uint256 b2, address o2, address p2, uint256 tot2) = ind.debugAvg(owner);
        emit log_named_uint("year after protect", y2);
        emit log_named_uint("lastTs after protect", t2);
        emit log_named_uint("acc after protect", a2);
        emit log_named_uint("lastBal after protect", b2);
        emit log_named_address("ownerLogical after protect", o2);
        emit log_named_address("primary after protect", p2);
        emit log_named_uint("totalNow after protect", tot2);

        vm.warp(block.timestamp + 20 days);
        vm.prank(owner);
        ind.unprotect(10 ether);

        (uint16 y3, uint64 t3, uint256 a3, uint256 b3, address o3, address p3, uint256 tot3) = ind.debugAvg(owner);
        emit log_named_uint("year after unprotect", y3);
        emit log_named_uint("lastTs after unprotect", t3);
        emit log_named_uint("acc after unprotect", a3);
        emit log_named_uint("lastBal after unprotect", b3);
        emit log_named_address("ownerLogical after unprotect", o3);
        emit log_named_address("primary after unprotect", p3);
        emit log_named_uint("totalNow after unprotect", tot3);

        vm.warp(block.timestamp + 30 days);
        emit log_named_uint("average now", ind.averageBalanceThisYear(owner));
    }
}
