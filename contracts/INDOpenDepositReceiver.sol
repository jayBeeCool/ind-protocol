// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IINDSale {
    function purchaseFor(address recipient, address refundTo) external payable;
}

contract INDOpenDepositReceiver {
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    IINDSale public immutable sale;

    error ZeroValue();

    constructor(address sale_) {
        require(sale_ != address(0), "sale=0");
        sale = IINDSale(sale_);
    }

    receive() external payable {
        _forward(msg.sender);
    }

    function deposit() external payable {
        _forward(msg.sender);
    }

    function _forward(address recipient) internal {
        if (msg.value == 0) revert ZeroValue();
        sale.purchaseFor{value: msg.value}(recipient, recipient);
    }
}
