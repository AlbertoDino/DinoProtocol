// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IWETH
/// @author dinoitaly@gmail.com
/// @notice Interface for Wrapped ETH (WETH) token
/// @dev Standard WETH interface for wrapping/unwrapping ETH
interface IWETH {

    /// @notice Wrap ETH to WETH
    /// @dev Sends ETH with the call to receive WETH
    function deposit() external payable;

    /// @notice Unwrap WETH to ETH
    /// @param amount Amount of WETH to unwrap
    function withdraw(uint256 amount) external;

    /// @notice Get WETH balance of address
    /// @param account Address to query
    /// @return WETH balance
    function balanceOf(address account) external view returns (uint256);

    /// @notice Transfer WETH tokens
    /// @param to Recipient address
    /// @param amount Amount to transfer
    /// @return Success flag
    function transfer(address to, uint256 amount) external returns (bool);
}
