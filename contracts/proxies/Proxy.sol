// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract Proxy is ERC1967Proxy {

    /// Proxy Wrapper
    /// @param logic_ logic contract address
    /// @param data_  inititalization data used in the delgate call
    constructor(address logic_, bytes memory data_) payable ERC1967Proxy(logic_, data_) {}

}