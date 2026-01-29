// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IOracle
/// @author dinoitaly@gmail.com
/// @notice Interface for the Oracle contract
/// @dev Defines price feed functions and oracle management
interface IOracle {

    /// @notice Oracle type enumeration
    enum OracleType {
        CHAINLINK,     // 0
        UNISWAP_TWAP,  // 1
        CUSTOM         // 2
    }

    /// @notice Oracle configuration data
    /// @param oracle Oracle/pool address
    /// @param stalenessThreshold Max age of price data
    /// @param decimals Price decimals
    /// @param isActive Whether oracle is active
    /// @param oracleType Type of oracle
    /// @param isToken0Stablecoin For Uniswap, whether token0 is stablecoin
    struct OracleData {
        address    oracle;
        uint256    stalenessThreshold;
        uint8      decimals;
        bool       isActive;
        OracleType oracleType;
        bool       isToken0Stablecoin;
    }

    // ** ----- Events ----- **

    /// @notice Emitted when oracle is added
    /// @param oracle Oracle address
    /// @param stanlessThreshold Staleness threshold
    event OracleAdded(address indexed oracle, uint256 stanlessThreshold);

    /// @notice Emitted when oracle is removed
    /// @param oracle Oracle address
    event OracleRemoved(address indexed oracle);

    /// @notice Emitted when price is updated
    /// @param price New price
    /// @param timestamp Update timestamp
    event PriceUpdated(uint256 price,uint256 timestamp);

    /// @notice Emitted when circuit breaker triggers
    /// @param newPrice New price that triggered breaker
    /// @param lastPrice Previous price
    event CircuitBreakTriggered(uint256 newPrice,uint256 lastPrice);

    // ** ----- Write Functions ----- **

    /// @notice Update aggregated ETH/USD price
    /// @return price Updated price
    function updateEthUscAggPrice() external returns (uint256 price);

    /// @notice Reset the circuit breaker
    function resetCircuitBreaker() external;

    /// @notice Deactivate oracle at index
    /// @param index Oracle index
    function deactivateOracle(uint256 index) external;

    /// @notice Activate oracle at index
    /// @param index Oracle index
    function activateOracle(uint256 index) external;

    /// @notice Set max price change threshold
    /// @param changeBps New threshold in basis points
    function setMaxPriceChangeBPS(uint256 changeBps) external;

    // ** ----- View Functions ----- **

    /// @notice Get WETH token address
    /// @return WETH address
    function getWethAddress() external view returns (address);

    /// @notice Get USDC token address
    /// @return USDC address
    function getUsdcAddress() external view returns (address);

    /// @notice Get DinoProtocol contract address
    /// @return DinoProtocol address
    function getDinoProtcolAddress() external view returns (address);

    /// @notice Get current ETH/USD price
    /// @return price Price in USD with 18 decimals
    function getEthUscPrice() external view returns (uint256 price);

    /// @notice Get last cached ETH/USD price
    /// @return price Last price
    function getLastEthUsdPrice() external view returns (uint256 price);

    /// @notice Get last price update timestamp
    /// @return Timestamp
    function getLastPriceTimestamp() external view returns (uint256);

    /// @notice Get circuit breaker cooldown
    /// @return Cooldown in seconds
    function getCircuitBreakerCoolDownHours() external view returns (uint256);

    /// @notice Check if circuit breaker is active
    /// @return True if broken
    function isCircuitBroken() external view returns (bool);

    /// @notice Get circuit breaker trigger timestamp
    /// @return Timestamp
    function getCircuitBrokenAt() external view returns (uint256);

    /// @notice Get number of configured oracles
    /// @return Oracle count
    function getOraclesCount() external view returns (uint256);

    /// @notice Get deviation threshold for outliers
    /// @return Threshold in basis points
    function getDeviationThresholdBps() external view returns (uint256);

    /// @notice Get max price change threshold
    /// @return Threshold in basis points
    function getMaxPriceChangeBps() external view returns (uint256);

    /// @notice Get default staleness threshold
    /// @return Threshold in seconds
    function getDefaultStalenessHours() external view returns (uint256);

    /// @notice Get oracle data by index
    /// @param index Oracle index
    /// @return OracleData struct
    function getOracleByIndex(uint256 index) external view returns (OracleData memory);

    /// @notice Get TWAP observation window
    /// @return Window in seconds
    function getTwapWindow() external view returns (uint32);

    /// @notice Get USDC decimal places
    /// @return Decimals
    function getUsdcDecimal() external view returns (uint8);
}
