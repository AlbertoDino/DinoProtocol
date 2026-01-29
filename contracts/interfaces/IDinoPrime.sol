// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IDinoPrime
/// @author dinoitaly@gmail.com
/// @notice Interface for the DinoPrime (DPRIME) token contract
/// @dev Defines mint/burn functions for the stablecoin token
interface IDinoPrime {

    /// @notice Mint DPRIME tokens
    /// @param to Recipient address
    /// @param amount Amount to mint
    function mint(address to, uint256 amount) external;

    /// @notice Burn DPRIME tokens from an address
    /// @param from Address to burn from
    /// @param amount Amount to burn
    function burnFrom(address from, uint256 amount) external;

    /// @notice Update DinoProtocol address
    /// @param procotol New DinoProtocol address
    function setDinoProtocol(address procotol) external;

    /// @notice Get DinoProtocol contract address
    /// @return DinoProtocol address
    function getDinoProtocol() external view returns (address);
}
