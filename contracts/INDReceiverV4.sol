// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IINDSaleV4 {
    function buyTo(address recipient, uint256 minOutWei) external payable;
}

contract INDReceiverV4 {
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    IINDSaleV4 public immutable sale;

    error ZeroValue();
    error ZeroRecipient();

    constructor(address sale_) {
        require(sale_ != address(0), "sale=0");
        sale = IINDSaleV4(sale_);
    }

    function buy(address recipient, uint256 minOutWei) public payable {
        if (msg.value == 0) revert ZeroValue();
        if (recipient == address(0)) revert ZeroRecipient();
        sale.buyTo{value: msg.value}(recipient, minOutWei);
    }

    receive() external payable {
        buy(msg.sender, 0);
    }
}
