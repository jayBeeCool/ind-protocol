// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IINDSaleV3 {
    function buyTo(address recipient, uint256 minOutWei) external payable;
}

contract INDReceiverV3 {
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    IINDSaleV3 public immutable sale;

    error ZeroValue();

    constructor(address sale_) {
        require(sale_ != address(0), "sale=0");
        sale = IINDSaleV3(sale_);
    }

    function buy(uint256 minOutWei) public payable {
        if (msg.value == 0) revert ZeroValue();
        sale.buyTo{value: msg.value}(msg.sender, minOutWei);
    }

    receive() external payable {
        buy(0);
    }
}
