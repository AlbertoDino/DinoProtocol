// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IUniswapV3Pool
/// @author dinoitaly@gmail.com
/// @notice Interface for Uniswap V3 Pool (subset for TWAP queries)
/// @dev From https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/pool/IUniswapV3PoolDerivedState.sol
interface IUniswapV3Pool {

    /// @notice Get token0 address
    /// @return Token0 address
    function token0() external view returns (address);

    /// @notice Get token1 address
    /// @return Token1 address
    function token1() external view returns (address);

    /// @notice Get pool fee tier
    /// @return Fee in hundredths of a bip
    function fee() external view returns(uint24);

    /// @notice Get tick spacing
    /// @return Tick spacing
    function tickSpacing() external view returns (int24);

    /// @notice Get current pool state
    /// @return sqrtPriceX96 Current price as sqrt(token1/token0) Q64.96
    /// @return tick Current tick
    /// @return observationIndex Index of last oracle observation
    /// @return observationCardinality Max observations stored
    /// @return observationCardinalityNext Next max observations
    /// @return feeProtocol Protocol fee
    /// @return unlocked Whether pool is unlocked
    function slot0() external view returns(
        uint160 sqrtPriceX96,
        int24   tick,
        uint16  observationIndex,
        uint16  observationCardinality,
        uint16  observationCardinalityNext,
        uint8   feeProtocol,
        bool    unlocked
    );

    /// @notice Returns cumulative tick and liquidity at each timestamp
    /// @dev Call with two values for TWAP: [windowSeconds, 0]
    /// @param secondsAgos Array of seconds ago timestamps
    /// @return tickCumulatives Cumulative tick values
    /// @return secondsPerLiquidityCumulativeX128s Cumulative liquidity
    function observe(uint32[] calldata secondsAgos) external view returns (
        int56[] memory tickCumulatives,
        uint160[] memory secondsPerLiquidityCumulativeX128s
    );

    /// @notice Get observation data at index
    /// @param index Observation index
    /// @return blockTimestamp Block timestamp
    /// @return tickCumulative Cumulative tick
    /// @return secondsPerLiquidityCumulativeX128 Cumulative liquidity
    /// @return initialized Whether observation is initialized
    function observations(uint256 index) external view returns (
        uint32 blockTimestamp,
        int56 tickCumulative,
        uint160 secondsPerLiquidityCumulativeX128,
        bool initialized
    );

}
