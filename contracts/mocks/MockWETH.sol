// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { IWETH } from "../interfaces/IWETH.sol";

/**
 * @title MockWETH
 * @notice WETH mock for testnet - wraps ETH
 */
contract MockWETH is ERC20, Ownable {
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    uint8 private constant DECIMALS = 18;

    constructor() ERC20("Wrapped Ether", "WETH") Ownable(msg.sender) {
        // Mint initial supply to deployer for liquidity setup
        _mint(msg.sender, 10_000_000 * 10**DECIMALS); // 10M
    }

    /// @notice Wrap ETH to WETH
    function deposit() public payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    /// @notice Unwrap WETH to ETH
    function withdraw(uint256 wad) public {
        require(balanceOf(msg.sender) >= wad, "Insufficient balance");
        _burn(msg.sender, wad);
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }

    /// @notice Anyone can mint test USDC (with cooldown)
    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }


    /// @notice Receive ETH and auto-wrap
    receive() external payable {
        deposit();
    }

    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
}