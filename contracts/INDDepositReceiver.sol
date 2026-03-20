// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IINDSaleReceiver {
    function purchaseFor(address recipient, address refundTo, uint256 minOutWei)
        external
        payable
        returns (uint256 outWei);
}

contract INDDepositReceiver {
    IINDSaleReceiver public immutable sale;
    address public immutable recipient;

    event DepositForwarded(address indexed from, address indexed recipient, uint256 ethIn, uint256 indOut);

    error ZeroSale();
    error ZeroRecipient();
    error ForwardFailed();

    constructor(address sale_, address recipient_) {
        if (sale_ == address(0)) revert ZeroSale();
        if (recipient_ == address(0)) revert ZeroRecipient();

        sale = IINDSaleReceiver(sale_);
        recipient = recipient_;
    }

    /// UX semplice: l'utente manda ETH normale a questo address e basta.
    receive() external payable {
        uint256 outWei = sale.purchaseFor{value: msg.value}(recipient, msg.sender, 0);
        emit DepositForwarded(msg.sender, recipient, msg.value, outWei);
    }

    /// Variante esplicita se vuoi supportare minOut lato dApp/wallet.
    function deposit(uint256 minOutWei) external payable returns (uint256 outWei) {
        outWei = sale.purchaseFor{value: msg.value}(recipient, msg.sender, minOutWei);
        emit DepositForwarded(msg.sender, recipient, msg.value, outWei);
    }

    fallback() external payable {
        revert ForwardFailed();
    }
}
