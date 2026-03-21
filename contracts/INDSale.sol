// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PriceCurve} from "./lib/PriceCurve.sol";

interface IINDSupply {
    function totalSupply() external view returns (uint256);
}

contract INDSale is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Burn sink irreversibile in pratica
    address payable public constant ETH_BURN_SINK = payable(0x000000000000000000000000000000000000dEaD);

    // Compat fallback only: if the token still exposes only mintWithMantissa(...)
    // the sale can still mint using a neutral fixed payload.
    uint64 public constant COMPAT_WAIT_SECONDS = 1 days;
    bytes32 public constant COMPAT_CHARACTERISTIC = bytes32(0);

    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    IINDSupply public immutable ind;

    event Bought(
        address indexed payer,
        address indexed refundTo,
        address indexed recipient,
        uint256 ethIn,
        uint256 ethUsed,
        uint256 ethRefunded,
        uint256 indOut
    );

    error ZeroValue();
    error ZeroRecipient();
    error ZeroRefundTo();
    error SlippageTooHigh();
    error ZeroOutput();
    error BurnFailed();
    error RefundFailed();
    error MintFailed();

    constructor(address admin, address indToken) {
        require(admin != address(0), "admin=0");
        require(indToken != address(0), "ind=0");

        ind = IINDSupply(indToken);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    /// Buy per se stessi: l'eventuale resto ETH torna al chiamante.
    function buy(uint256 minOutWei) external payable returns (uint256 outWei) {
        return _purchaseFor(msg.sender, msg.sender, minOutWei);
    }

    /// Buy verso un recipient specifico: l'eventuale resto ETH torna al chiamante.
    function buyTo(address recipient, uint256 minOutWei) external payable returns (uint256 outWei) {
        return _purchaseFor(recipient, msg.sender, minOutWei);
    }

    /// Variante generica utile per receiver/proxy di deposito:
    /// - recipient = chi riceve gli IND
    /// - refundTo  = chi riceve il resto ETH
    function purchaseFor(address recipient, address refundTo, uint256 minOutWei)
        external
        payable
        returns (uint256 outWei)
    {
        return _purchaseFor(recipient, refundTo, minOutWei);
    }

    function _purchaseFor(address recipient, address refundTo, uint256 minOutWei)
        internal
        nonReentrant
        returns (uint256 outWei)
    {
        if (msg.value == 0) revert ZeroValue();
        if (recipient == address(0)) revert ZeroRecipient();
        if (refundTo == address(0)) revert ZeroRefundTo();

        uint256 currentSupply = ind.totalSupply();

        outWei = PriceCurve.quoteBuy(currentSupply, msg.value);
        if (outWei == 0) revert ZeroOutput();
        if (outWei < minOutWei) revert SlippageTooHigh();

        uint256 ethUsed = PriceCurve.costToMint(currentSupply, outWei);
        uint256 refund = msg.value - ethUsed;

        // forge-lint: disable-next-line(mixed-case-function)
        _mintIND(recipient, outWei);

        (bool burnOk,) = ETH_BURN_SINK.call{value: ethUsed}("");
        if (!burnOk) revert BurnFailed();

        if (refund > 0) {
            (bool refundOk,) = payable(refundTo).call{value: refund}("");
            if (!refundOk) revert RefundFailed();
        }

        emit Bought(msg.sender, refundTo, recipient, msg.value, ethUsed, refund, outWei);
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function _mintIND(address recipient, uint256 amountWei) internal {
        // Preferred modern path: mint(address,uint256)
        {
            (bool ok, bytes memory ret) =
                address(ind).call(abi.encodeWithSignature("mint(address,uint256)", recipient, amountWei));
            if (ok) {
                if (ret.length == 0 || abi.decode(ret, (bool))) return;
            }
        }

        // Backward-compatible path: mintWithMantissa(address,uint256,uint64,bytes32)
        {
            (bool ok, bytes memory ret) = address(ind)
                .call(
                    abi.encodeWithSignature(
                        "mintWithMantissa(address,uint256,uint64,bytes32)",
                        recipient,
                        amountWei,
                        COMPAT_WAIT_SECONDS,
                        COMPAT_CHARACTERISTIC
                    )
                );
            if (ok) {
                if (ret.length == 0 || abi.decode(ret, (bool))) return;
            }
        }

        revert MintFailed();
    }

    receive() external payable {
        revert("use buy");
    }

    fallback() external payable {
        revert("use buy");
    }
}
