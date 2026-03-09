// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./lib/PriceCurve.sol";

interface IINDMintable {
    function totalSupply() external view returns (uint256);
    function mintWithMantissa(
        address to,
        uint256 amount,
        uint64 mantissaSeconds,
        bytes32 characteristic
    ) external returns (bool);
}

contract INDSale is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    uint64 public constant MIN_MANTISSA_SECONDS = 1 days;

    // Burn sink irreversibile in pratica
    address payable public constant ETH_BURN_SINK =
        payable(0x000000000000000000000000000000000000dEaD);

    IINDMintable public immutable ind;

    event Bought(
        address indexed buyer,
        address indexed recipient,
        uint256 ethIn,
        uint256 ethUsed,
        uint256 ethRefunded,
        uint256 indOut,
        uint64 mantissaSeconds,
        bytes32 indexed characteristic
    );

    error ZeroValue();
    error ZeroRecipient();
    error SlippageTooHigh();
    error ZeroOutput();
    error BurnFailed();
    error RefundFailed();
    error InvalidMantissa();

    constructor(address admin, IINDMintable indToken) {
        require(admin != address(0), "admin=0");
        require(address(indToken) != address(0), "ind=0");

        ind = indToken;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    /// Buy per se stessi, lock minimo 1 giorno.
    function buy(uint256 minOutWei) external payable returns (uint256 outWei) {
        return buyTo(msg.sender, minOutWei, MIN_MANTISSA_SECONDS, bytes32(0));
    }

    /// Buy verso recipient con characteristic custom, ma mantissa sempre >= 1 giorno.
    function buyTo(
        address recipient,
        uint256 minOutWei,
        uint64 mantissaSeconds,
        bytes32 characteristic
    ) public payable nonReentrant returns (uint256 outWei) {
        if (msg.value == 0) revert ZeroValue();
        if (recipient == address(0)) revert ZeroRecipient();
        if (mantissaSeconds < MIN_MANTISSA_SECONDS) revert InvalidMantissa();

        uint256 currentSupply = ind.totalSupply();

        outWei = PriceCurve.quoteBuy(currentSupply, msg.value);
        if (outWei == 0) revert ZeroOutput();
        if (outWei < minOutWei) revert SlippageTooHigh();

        uint256 ethUsed = PriceCurve.costToMint(currentSupply, outWei);
        uint256 refund = msg.value - ethUsed;

        // mint IND locked
        bool ok = ind.mintWithMantissa(recipient, outWei, mantissaSeconds, characteristic);
        require(ok, "mint-failed");

        // burn ETH used
        (bool burnOk, ) = ETH_BURN_SINK.call{value: ethUsed}("");
        if (!burnOk) revert BurnFailed();

        // refund excess ETH
        if (refund > 0) {
            (bool refundOk, ) = payable(msg.sender).call{value: refund}("");
            if (!refundOk) revert RefundFailed();
        }

        emit Bought(
            msg.sender,
            recipient,
            msg.value,
            ethUsed,
            refund,
            outWei,
            mantissaSeconds,
            characteristic
        );
    }

    receive() external payable {
        revert("use buy");
    }

    fallback() external payable {
        revert("use buy");
    }
}
