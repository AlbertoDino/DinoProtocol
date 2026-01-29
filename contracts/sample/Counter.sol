// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract Counter {
    uint public count;

    event Increment();

    constructor() {
        count = 0;
    }

    function incBy(uint v) public {
        count += v;
        emit Increment();
    }

    function increment() public {
        count += 1;
        emit Increment();
    }

    function decrement() public {
        require(count > 0, "Counter can't go below 0");
        count -= 1;
    }
}