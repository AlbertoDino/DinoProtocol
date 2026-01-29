// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ICollateralVault
/// @author dinoitaly@gmail.com
/// @notice Interface for the CollateralVault contract
/// @dev Defines deposit, withdrawal, and view functions for collateral management
interface ICollateralVault
{
    // ** ----- Events ----- **

    /// @notice Emitted when collateral is deposited
    /// @param from Depositor address
    /// @param amount Amount deposited
    event Deposited(address indexed from, uint256 amount);

    /// @notice Emitted when collateral is withdrawn
    /// @param to Recipient address
    /// @param amount Amount withdrawn
    event Withdrawn(address indexed to, uint256 amount);

    // ** ----- Write Functions ----- **

    /// @notice Deposit WETH into the vault
    /// @param amount Amount of WETH to deposit
    function deposit(uint256 amount) external;

    /// @notice Deposit ETH into the vault (auto-wraps to WETH)
    function depositETH() external payable;

    /// @notice Withdraw collateral as ETH
    /// @param to Recipient address
    /// @param amount Amount to withdraw
    function withdrawEth(address to, uint256 amount) external;

    // ** ----- View Functions ----- **

    /// @notice Get total collateral in vault
    /// @return Total collateral in ETH/WETH
    function getTotalCollateralEth() external view returns (uint256);

    /// @notice Get DinoProtocol contract address
    /// @return DinoProtocol address
    function getDinoProtocol() external view returns (address);

    /// @notice Get WETH token address
    /// @return WETH address
    function getWethAddress() external view returns (address);

}
