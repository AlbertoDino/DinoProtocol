// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title WadMath
/// @author dinoitaly@gmail.com
/// @notice Fixed-point math library for 18-decimal "wad" format
/// @dev Safe arithmetic for USD/ETH price calculations with overflow protection
library WadMath {

    uint256 internal constant WAD = 1e18;
    uint256 internal constant BPS = 10000; // Basis points

    /// @notice Multiply two wad values
    /// @dev (a * b) / 1e18 with overflow protection
    /// @param a First operand (18 decimals)
    /// @param b Second operand (18 decimals)
    /// @return Result in wad format (18 decimals)
    function wadMul(uint256 a,uint256 b) internal pure returns (uint256) {
        return Math.mulDiv(a, b, WAD);  // (a * b) / 1e18
    }

    /// @notice Divide two wad values
    /// @dev (a * 1e18) / b with overflow protection
    /// @param a Numerator (18 decimals)
    /// @param b Denominator (18 decimals)
    /// @return Result in wad format (18 decimals)
    function wadDiv(uint256 a,uint256 b) internal pure returns (uint256) {
        return Math.mulDiv(a, WAD, b); // (a * 1e18) / b
    }

    /// @notice Multiply by basis points
    /// @dev (a * b) / 10000
    /// @param a Value to multiply
    /// @param b Basis points (100 = 1%)
    /// @return Result after applying basis points
    function bpsMul(uint256 a,uint256 b) internal pure returns (uint256) {
        return Math.mulDiv(a, b, BPS);  // (a * 10000) / b
    }

    /// @notice Normalize a price to 18 decimal wad format
    /// @dev Scales up or down based on source decimals
    /// @param price Price value to normalize
    /// @param decimals Source decimal places
    /// @return Normalized price with 18 decimals
    function normalizeToWad(uint256 price, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return price;

        if (decimals < 18) {
            return price * (10 ** (18 - decimals));
        } else {
            return price / (10 ** (decimals - 18));
        }
    }

    /// @notice Calculate absolute difference between two values
    /// @param a First value
    /// @param b Second value
    /// @return Absolute difference |a - b|
    function absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    /// @notice Calculate collateral ratio
    /// @dev CR = collateral / debt, returns max uint256 if debt is zero
    /// @param collateralUsd Collateral value in USD (18 decimals)
    /// @param debtUsd Debt value in USD (18 decimals)
    /// @return Collateral ratio in wad format
    function calculateCR(uint256 collateralUsd,uint256 debtUsd) internal pure returns (uint256) {
        if(debtUsd == 0) return type(uint256).max;
        return wadDiv(collateralUsd, debtUsd);
    }

    /// @notice Cap a value at 100% (10000 basis points)
    /// @param v Value to cap
    /// @return Capped value, max 10000
    function capAt100Bps(uint256 v) internal pure returns (uint256)
    {
        return v > BPS ? BPS : v;
    }


}
