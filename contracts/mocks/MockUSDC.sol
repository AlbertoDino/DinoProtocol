// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockUSDC
 * @notice USDC mock for testnet - 6 decimals, free minting
 */
contract MockUSDC is ERC20, Ownable {
    uint8 private constant DECIMALS = 6;
    
    /// @notice Max mint per call (100,000 USDC)
    uint256 public constant MAX_MINT = 100_000 * 10**DECIMALS;
    
    /// @notice Cooldown between mints (1 hour)
    uint256 public constant MINT_COOLDOWN = 1 hours;
    
    /// @notice Track last mint time per address
    mapping(address => uint256) public lastMintTime;

    constructor() ERC20("USD Coin", "USDC") Ownable(msg.sender) {
        // Mint initial supply to deployer for liquidity setup
        _mint(msg.sender, 10_000_000 * 10**DECIMALS); // 10M USDC
    }

    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    /// @notice Anyone can mint test USDC (with cooldown)
    function mint(uint256 amount) external {
        require(amount <= MAX_MINT, "Exceeds max mint");
        require(
            block.timestamp >= lastMintTime[msg.sender] + MINT_COOLDOWN,
            "Cooldown not elapsed"
        );
        
        lastMintTime[msg.sender] = block.timestamp;
        _mint(msg.sender, amount);
    }

    /// @notice Owner can mint any amount (for initial setup)
    function ownerMint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
