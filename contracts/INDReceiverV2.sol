// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IINDSaleV2 {
    function purchaseFor(address recipient, address refundTo) external payable;
}

contract INDReceiverV2 {
    IINDSaleV2 public immutable sale;

    error ZeroValue();

    constructor(address sale_) {
        require(sale_ != address(0), "sale=0");
        sale = IINDSaleV2(sale_);
    }

    function buy() public payable {
        if (msg.value == 0) revert ZeroValue();
        sale.purchaseFor{value: msg.value}(msg.sender, msg.sender);
    }

    receive() external payable {
        buy();
    }
}
