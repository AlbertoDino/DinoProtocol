// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IUniswapV3Pool } from "../interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @title UniswapV3
/// @author dinoitaly@gmail.com
/// @notice Uniswap V3 TWAP price oracle library for DinoProtocol
/// @dev Provides TWAP and spot price calculations from Uniswap V3 pools
library UniswapV3 {

    // ** ----- Constant ----- **

    uint32 public constant DEFAULT_TWAP_WINDOW = 1800; // 30 minutes
    uint32 public constant MIN_TWAP_WINDOW     = 60; // 1 minute
    uint256 internal constant Q96              = 0x1000000000000000000000000;
    uint256 internal constant Q192             = Q96 * Q96;

    // ** ----- Errors ----- **

    error ZeroAddress();
    error InvalidPool();
    error InsufficientObservations();
    error InvalidTWAPWindow();
    error StaleObservation();

    /// @notice Parameters for TWAP price calculation
    /// @param pool Uniswap V3 pool address
    /// @param decimals Stablecoin decimals
    /// @param twapWindow TWAP observation window in seconds
    /// @param isToken0Stablecoin True if stablecoin is token0 in the pool
    struct TwapParams {
        address pool;
        uint8   decimals;
        uint32  twapWindow;
        bool    isToken0Stablecoin;
    }

    /// @notice Get TWAP price of ETH in USD from Uniswap V3 pool
    /// @dev Calculates time-weighted average price over the specified window
    /// @param arg TWAP configuration parameters
    /// @return isValid Whether the price calculation succeeded
    /// @return price ETH price in USD with 18 decimals
    function getTwapPrice(TwapParams memory arg) internal view returns (bool isValid, uint256 price)
    {
        if(arg.pool == address(0)) revert ZeroAddress();

        if(arg.twapWindow < MIN_TWAP_WINDOW) {
            return (false, 0);
        }


        try IUniswapV3Pool(arg.pool).observe(_getSecondsAgo(arg.twapWindow)) returns (
            int56[] memory tickCumulatives,
             uint160[] memory )
        {
             // Calculate arithmetic mean tick
            int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
            int24 arithmeticMeanTick  = int24(tickCumulativesDelta / int56(uint56(arg.twapWindow)));

            // Round to negative infinity (Uniswap convention)
            if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(uint56(arg.twapWindow)) != 0))
            {
                arithmeticMeanTick--;
            }

            price   = _getQuoteAtTick(arithmeticMeanTick, arg.isToken0Stablecoin, arg.decimals);
            isValid = price > 0;
        } catch {
            return (false, 0);
        }
    }

    /// @notice Get current spot price from Uniswap V3 pool (not TWAP)
    /// @dev Uses current tick from slot0
    /// @param arg TWAP configuration parameters
    /// @return valid Whether the price is valid
    /// @return price Current ETH price in USD with 18 decimals
    function getSpotPrice(TwapParams memory arg) internal view
        returns (bool valid, uint256 price)
    {
        if(arg.pool == address(0)) revert ZeroAddress();

        try IUniswapV3Pool(arg.pool).slot0() returns (
            uint160,
            int24 tick,
            uint16,
            uint16,
            uint16,
            uint8,
            bool
        ) {
            price = _getQuoteAtTick(
                tick,
                arg.isToken0Stablecoin,
                arg.decimals
            );
            valid = price > 0;
        } catch {
            return (false, 0);
        }
    }

    /// @notice Check if pool has sufficient observation history for TWAP
    /// @dev Verifies the pool has observations older than the required window
    /// @param pool Pool address
    /// @param requiredWindow Required observation window in seconds
    /// @return sufficient True if pool has enough history
    /// @return oldestAvailable Oldest available observation timestamp
    function checkObservationHistory(address pool, uint32 requiredWindow) internal view
        returns (bool sufficient, uint256 oldestAvailable)
    {
        try IUniswapV3Pool(pool).slot0() returns (
            uint160,
            int24,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16,
            uint8,
            bool
        ) {
            if (observationCardinality == 0) {
                return (false, 0);
            }

            // Get oldest observation
            uint16 oldestIndex = (observationIndex + 1) % observationCardinality;

            try IUniswapV3Pool(pool).observations(oldestIndex) returns (
                uint32 blockTimestamp,
                int56,
                uint160,
                bool initialized
            ) {
                if (!initialized) {
                    return (false, 0);
                }

                oldestAvailable = blockTimestamp;
                uint256 age     = block.timestamp - blockTimestamp;
                sufficient      = age >= requiredWindow;
            } catch {
                return (false, 0);
            }
        } catch {
            return (false, 0);
        }
    }

    /// @notice Validate pool configuration for WETH/stablecoin pair
    /// @dev Checks that pool contains expected WETH and stablecoin tokens
    /// @param pool Pool address
    /// @param expectedWETH Expected WETH address
    /// @param expectedStable Expected stablecoin address
    /// @return valid True if pool is valid
    /// @return isToken0Stable True if stablecoin is token0
    function validatePool(
        address pool,
        address expectedWETH,
        address expectedStable
    ) internal view
        returns (bool valid, bool isToken0Stable)
    {
        try IUniswapV3Pool(pool).token0() returns (address token0) {
            try IUniswapV3Pool(pool).token1() returns (address token1) {
                if (token0 == expectedStable && token1 == expectedWETH) {
                    return (true, true);
                }
                if (token0 == expectedWETH && token1 == expectedStable) {
                    return (true, false);
                }
                return (false, false);
            } catch {
                return (false, false);
            }
        } catch {
            return (false, false);
        }
    }
    // ** ----- Internals ----- **

    /// @notice Build secondsAgo array for observe() call
    /// @param twapWindow TWAP window in seconds
    /// @return secondsAgo Array with [twapWindow, 0]
    function _getSecondsAgo(uint32 twapWindow) internal pure returns (uint32[] memory secondsAgo)
    {
        secondsAgo    = new uint32[](2);
        secondsAgo[0] = twapWindow;
        secondsAgo[1] = 0;
    }

    /// @notice Convert tick to price quote with decimal adjustment
    /// @dev Handles both token0=stablecoin and token0=WETH configurations
    /// @param tick Uniswap V3 tick value
    /// @param isStablecoin True if token0 is the stablecoin
    /// @param decimals Stablecoin decimal places
    /// @return price ETH price in USD with 18 decimals
    function _getQuoteAtTick(int24 tick, bool isStablecoin, uint8 decimals) internal pure
        returns (uint256 price)
    {
        require(decimals <= 36, "Decimals too high");
        // Get sqrtPriceX96 from tick
        uint160 sqrtPriceX96 = _getSqrtRatioAtTick(tick);
        uint256 sqrtPrice    = uint256(sqrtPriceX96);

        if (sqrtPrice == 0) return 0;

        uint256 sqrtPriceSquared = sqrtPrice * sqrtPrice;

        if(isStablecoin)
        {
            /*
            * token0 = USDC (6 decimals), token1 = WETH (18 decimals)
            *
            * to avoid overflow we are splitting the calculation into sqrts
            * sqrtPriceX96² / 2^192 = WETH_wei / USDC_units
            * = (Q96 × 10^15 / sqrtPrice)²
            */

            // sqrt of decimal adjustment: 10^((36 - decimals) / 2)
            // For USDC (6 decimals): 10^15
            // For DAI (18 decimals): 10^9
            uint256 sqrtDecimalAdjustment = 10 ** ((36 - decimals) / 2);

             // Calculate: (Q96 * sqrtDecimalAdjustment / sqrtPrice)²
            uint256 intermediate = (Q96 * sqrtDecimalAdjustment) / sqrtPrice;
            price = intermediate * intermediate;

            // Handle odd decimal adjustment (rare case)
            if ((36 - decimals) % 2 == 1) {
                price = price * 10;
            }
        }
        else
        {
           /*
            * token0 = WETH (18 decimals), token1 = USDC (6 decimals)
            *
            * sqrtPriceX96² / 2^192 = USDC_units / WETH_wei
            *
            * This directly gives us "USDC units per wei"
            *
            * Step 1: Get USDC_units per WETH_wei
            *         = sqrtPriceX96² / 2^192
            *
            * Step 2: Convert to "USDC per 1 ETH"
            *         Multiply by 10^18 (1 ETH = 10^18 wei)
            *
            * Step 3: Convert USDC units to 18 decimals
            *         Multiply by 10^(18 - stableDecimals)
            *         For USDC: multiply by 10^12
            *
            * Combined: (sqrtPrice² / 2^192) * 10^18 * 10^(18-6)
            *         = (sqrtPrice² * 10^30) / 2^192
            */

            // Factor = 10^(36 - stableDecimals) = 10^30 for USDC
            uint256 decimalAdjustment = 10 ** (36 - decimals);

            // sqrtPriceSquared * decimalAdjustment / Q192
            // Split to avoid overflow
            uint256 numerator = sqrtPriceSquared / Q96;  // Divide by 2^96 first
            price = (numerator * decimalAdjustment) / Q96;  // Divide by 2^96 again
        }
    }

    /// @notice Calculate sqrt(1.0001^tick) * 2^96
    /// @dev Derived from Uniswap V3 TickMath library
    /// @param tick The tick value
    /// @return sqrtPriceX96 The sqrt price as Q64.96
    function _getSqrtRatioAtTick(int24 tick) internal pure returns (uint160 sqrtPriceX96)
    {
        uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));
        require(absTick <= uint256(int256(887272)), "T");

        // Magic numbers from Uniswap V3 TickMath
        uint256 ratio = absTick & 0x1 != 0
            ? 0xfffcb933bd6fad37aa2d162d1a594001
            : 0x100000000000000000000000000000000;

        if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
        if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
        if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
        if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
        if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
        if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
        if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
        if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
        if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
        if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
        if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
        if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
        if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
        if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
        if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
        if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
        if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
        if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
        if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

        if (tick > 0) ratio = type(uint256).max / ratio;

        sqrtPriceX96 = uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    }
}
