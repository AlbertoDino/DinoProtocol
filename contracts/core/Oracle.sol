// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Initializable }            from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { PausableUpgradeable }      from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { UUPSUpgradeable }          from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { AggregatorV3Interface }    from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { UniswapV3 }                from "../libraries/UniswapV3.sol";
import { IOracle }                  from "../interfaces/IOracle.sol";
import { WadMath }                  from "../libraries/WadMath.sol";

/// @title Oracle
/// @author dinoitaly@gmail.com
/// @notice Multi-source price oracle with circuit breaker protection for DinoProtocol
/// @dev Aggregates prices from Chainlink and Uniswap V3 TWAP with median calculation
contract Oracle is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    IOracle
{

    using WadMath for uint256;

    // ** ----- Roles ----- **

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // ** ----- Constants ----- **

    uint256 internal constant DEVIATION_THRESHOLD_BPS = 200;  // 2%
    uint256 internal constant MAX_PRICE_CHANGE_BPS    = 1000; // 10%
    uint256 internal constant DEFAULT_STALENESS       = 4 hours;

    // ** ----- Variables ----- **

    /// @notice Array of configured oracles
    OracleData[] internal oracles;

    /// @notice Max price deviation BPS
    uint256 internal max_price_change_bps;

    /// @notice Last validated price (18 decimals)
    uint256 internal lastPrice;

    /// @notice Timestamp of last valid price
    uint256 internal lastPriceTimestamp;

    /// @notice Circuit breaker state
    bool internal circuitBroken;

    /// @notice Circuit breaker trigger timestamp
    uint256 internal circuitBrokenAt;

    /// @notice Circuit breaker cooldown period
    uint256 internal circuitBreakerCooldown;

    /// @notice WETH address
    address internal weth;

    /// @notice USDC address
    address internal usdc;

    /// @notice The number of decimals used for USDC
    uint8 internal usdcDecimal;

    /// @notice Reference to DinoProtocol
    address internal dinoProtocol;

    /// --- Uniwap TWAP V3 Configuration ---

    /// @notice TWAP observation window
    uint32 internal twapWindow;

    // ** ----- Events ----- **
    event MaxChangePriceDeviationChanged(uint256 oldbps, uint256 newbps);
    event OracleActivated (uint256 indexed index, address oracle, OracleType OracleType);
    event OracleDeactivated (uint256 indexed index);
    event CircuitBreakReset();
    event DinoProtocolSet(address dinoProtocol);

    // ** ----- Errors ----- **
    error ZeroAddress();
    error InvalidChangeBps();
    error InvalidOracle();
    error CircuitBroken();
    error NoPriceAvailable();
    error NoActiveOracles();
    error InvalidTwapConfig(bool,bool);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the Oracle contract
    /// @dev Sets up roles, token addresses, and default parameters
    /// @param admin Admin address with DEFAULT_ADMIN_ROLE
    /// @param weth_ WETH token address
    /// @param usdc_ USDC token address
    /// @param dinoProtocol_ DinoProtocol contract address
    function initialize(
        address admin,
        address weth_,
        address usdc_,
        address dinoProtocol_) external initializer {

        if(admin == address(0) || weth_ == address(0)  || usdc_ == address(0) || dinoProtocol_ == address(0)) revert ZeroAddress();

        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        weth                   = weth_;
        usdc                   = usdc_;
        dinoProtocol           = dinoProtocol_;
        usdcDecimal            = 6;
        circuitBreakerCooldown = 1 hours;
        twapWindow             = 30 minutes;
        circuitBroken          = false;
        circuitBrokenAt        = 0;
        max_price_change_bps   = MAX_PRICE_CHANGE_BPS;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(UPGRADER_ROLE, dinoProtocol_);
        _grantRole(OPERATOR_ROLE, dinoProtocol_);

    }

    /// @notice Add a Chainlink price feed oracle
    /// @dev Only callable by DEFAULT_ADMIN_ROLE
    /// @param oracle Chainlink aggregator address
    /// @param stalenessThreshold Max age of price data in seconds
    function addChainLinkOracle(address oracle, uint256 stalenessThreshold) external onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if(oracle ==  address(0)) revert ZeroAddress();

        uint8 decimals = AggregatorV3Interface(oracle).decimals();

        _addOracle(oracle, decimals, stalenessThreshold, OracleType.CHAINLINK, true);
    }

    /// @notice Add a Uniswap V3 TWAP oracle
    /// @dev Only callable by DEFAULT_ADMIN_ROLE, validates pool configuration
    /// @param pool_ Uniswap V3 pool address
    function addUniswapTwap(address pool_) external onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if(pool_ == address(0)) revert ZeroAddress();

         // Validate pool configuration
        (bool isValid, bool isToken0stable) = UniswapV3.validatePool(pool_,weth,usdc);

        if(!isValid)
            revert InvalidTwapConfig(isValid,isToken0stable);

        _addOracle(pool_, usdcDecimal, DEFAULT_STALENESS, OracleType.UNISWAP_TWAP, isToken0stable);

    }

    // ** ----- Write Functions ----- **

    /// @notice Update ETH/USD price from all active oracles
    /// @dev Triggers circuit breaker if price deviation exceeds threshold
    /// @return price Aggregated ETH price in USD (18 decimals)
    function updateEthUscAggPrice() external override onlyRole(OPERATOR_ROLE) returns (uint256 price)
    {
        (bool isValid, uint256 price_) = _getAggregatePrice();

        if(!isValid) {
            revert NoPriceAvailable();
        }

        // check for price deviation
        if(lastPrice > 0)
        {
            uint256 deviation = price_.absDiff(lastPrice) * 10000 / lastPrice;

            if (deviation > max_price_change_bps) {
                circuitBroken   =  true;
                circuitBrokenAt = block.timestamp;
                emit CircuitBreakTriggered(price_,lastPrice);
                return lastPrice;
            }
        }

        lastPrice          = price_;
        lastPriceTimestamp = block.timestamp;

        emit PriceUpdated(price, block.timestamp);
        price = lastPrice;
    }

    /// @notice Reset the circuit breaker
    /// @dev Only callable by DEFAULT_ADMIN_ROLE
    function resetCircuitBreaker() external override onlyRole(DEFAULT_ADMIN_ROLE)
    {
        circuitBroken   = false;
        circuitBrokenAt = 0;
        emit CircuitBreakReset();
    }

    /// @notice Deactivate an oracle by index
    /// @dev Only callable by DEFAULT_ADMIN_ROLE
    /// @param index Oracle index in the array
    function deactivateOracle(uint256 index) external override onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (index >= oracles.length) revert InvalidOracle();
        oracles[index].isActive = false;
        emit OracleDeactivated(index);
    }

    /// @notice Activate an oracle by index
    /// @dev Only callable by DEFAULT_ADMIN_ROLE
    /// @param index Oracle index in the array
    function activateOracle(uint256 index) external override onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (index >= oracles.length) revert InvalidOracle();
        oracles[index].isActive = true;

        emit OracleActivated(index, oracles[index].oracle ,oracles[index].oracleType );
    }

    /// @notice Set maximum price change threshold for circuit breaker
    /// @dev Only callable by DEFAULT_ADMIN_ROLE
    /// @param changeBps New threshold in basis points
    function setMaxPriceChangeBPS(uint256 changeBps) external override onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if(changeBps == 0) revert InvalidChangeBps();

        uint256 oldbps = max_price_change_bps;
        max_price_change_bps = changeBps;

        emit MaxChangePriceDeviationChanged(oldbps, changeBps);
    }

    /// @notice Update DinoProtocol address and transfer roles
    /// @dev Only callable by DEFAULT_ADMIN_ROLE
    /// @param protocol New DinoProtocol contract address
    function setDinoProtocol(address protocol) onlyRole(DEFAULT_ADMIN_ROLE) external
    {
        if(protocol == address(0)) revert ZeroAddress();

        _revokeRole(UPGRADER_ROLE, dinoProtocol);
        _revokeRole(OPERATOR_ROLE, dinoProtocol);

        dinoProtocol = protocol;

       _grantRole(UPGRADER_ROLE,dinoProtocol);
       _grantRole(OPERATOR_ROLE,dinoProtocol);

        emit DinoProtocolSet(dinoProtocol);
    }

    // ** ----- View Functions ----- **

    /// @notice Get WETH token address
    /// @return WETH address
    function getWethAddress() external view returns (address)
    {
        return weth;
    }

    /// @notice Get USDC token address
    /// @return USDC address
    function getUsdcAddress() external view returns (address)
    {
        return usdc;
    }

    /// @notice Get DinoProtocol contract address
    /// @return DinoProtocol address
    function getDinoProtcolAddress() external view returns (address)
    {
        return dinoProtocol;
    }

    /// @notice Get current ETH/USD price from aggregated oracles
    /// @dev Reverts if circuit breaker is active or no valid price available
    /// @return ETH price in USD (18 decimals)
    function getEthUscPrice() external view override returns (uint256)
    {
        if(_isCircuitBroken()) {
            revert CircuitBroken();
        }

        (bool isValid, uint256 price_) = _getAggregatePrice();

        if(isValid) {
            return price_;
        }

        if(lastPrice > 0 && (block.timestamp - lastPriceTimestamp < DEFAULT_STALENESS))
        {
            return lastPrice;
        }

        revert NoPriceAvailable();
    }

    /// @notice Get last cached ETH/USD price
    /// @return price Last validated price (18 decimals)
    function getLastEthUsdPrice() external view override returns (uint256 price)
    {
        return lastPrice;
    }

    /// @notice Get timestamp of last price update
    /// @return Last price update timestamp
    function getLastPriceTimestamp() external view returns (uint256)
    {
        return lastPriceTimestamp;
    }

    /// @notice Get circuit breaker cooldown period
    /// @return Cooldown period in seconds
    function getCircuitBreakerCoolDownHours() external view returns (uint256)
    {
        return circuitBreakerCooldown;
    }

    /// @notice Check if circuit breaker is currently active
    /// @return True if circuit breaker is active
    function isCircuitBroken() external view override returns (bool)
    {
        return _isCircuitBroken();
    }

    /// @notice Get timestamp when circuit breaker was triggered
    /// @return Circuit breaker trigger timestamp
    function getCircuitBrokenAt() external view returns (uint256)
    {
        return circuitBrokenAt;
    }

    /// @notice Get total number of configured oracles
    /// @return Number of oracles
    function getOraclesCount() external view returns (uint256)
    {
        return oracles.length;
    }

    /// @notice Get oracle data at specific index
    /// @param index Oracle index
    /// @return OracleData struct
    function getOracleAtIndex(uint256 index) external view  returns (OracleData memory)
    {
        return oracles[index];
    }

    /// @notice Get deviation threshold for outlier detection
    /// @return Threshold in basis points
    function getDeviationThresholdBps() external pure returns (uint256)
    {
        return DEVIATION_THRESHOLD_BPS;
    }

    /// @notice Get maximum price change threshold
    /// @return Threshold in basis points
    function getMaxPriceChangeBps() external view returns (uint256)
    {
        return max_price_change_bps;
    }

    /// @notice Get default staleness threshold
    /// @return Staleness threshold in seconds
    function getDefaultStalenessHours() external pure returns (uint256)
    {
        return DEFAULT_STALENESS;
    }

    /// @notice Get oracle data by index
    /// @param index Oracle index
    /// @return OracleData struct
    function getOracleByIndex(uint256 index) external view returns (OracleData memory)
    {
        return oracles[index];
    }

    /// @notice Get TWAP observation window
    /// @return Window in seconds
    function getTwapWindow() external view returns (uint32)
    {
        return twapWindow;
    }

    /// @notice Get USDC decimal places
    /// @return Number of decimals
    function getUsdcDecimal() external view returns (uint8)
    {
        return usdcDecimal;
    }

    // ** ----- Internal Functions ----- **

    /// @notice Get aggregated price from all active oracles
    /// @dev Calculates median of valid prices, skips stale or invalid sources
    /// @return bool Whether the price is valid
    /// @return uint256 Aggregated price (18 decimals)
    function _getAggregatePrice() internal view returns (bool, uint256) {
        uint256[] memory prices = new uint256[](oracles.length);
        uint256 validPriceCount = 0;

        for(uint256 i = 0; i < oracles.length; i++) {
            OracleData memory ioracle = oracles[i];

            if(!ioracle.isActive) continue;

            // Collect Chainlink price
            if(ioracle.oracleType == OracleType.CHAINLINK)
            {
                try AggregatorV3Interface(ioracle.oracle).latestRoundData() returns (
                    uint80  /*roundId*/,
                    int256  answer,
                    uint256 /*startedAt*/,
                    uint256 updatedAt,
                    uint80  /*answeredInRound*/)
                    {
                        // Stanless Check
                        if((block.timestamp - updatedAt) > ioracle.stalenessThreshold)
                        {
                            continue;
                        }

                        if(answer <= 0) { continue; }

                        uint256 price = uint256(answer).normalizeToWad(ioracle.decimals);

                        prices[validPriceCount] = price;
                        validPriceCount++;
                    }
                catch  {
                    continue;
                }
            }

            // Collect TWAP price
            if(ioracle.oracleType == OracleType.UNISWAP_TWAP)
            {

                (bool isValid, uint256 price) = UniswapV3.getTwapPrice(UniswapV3.TwapParams({
                    pool         : ioracle.oracle,
                    decimals     : ioracle.decimals,
                    twapWindow   : twapWindow,
                    isToken0Stablecoin : ioracle.isToken0Stablecoin
                }));

                if(isValid && price > 0)
                {
                    prices[validPriceCount] = price;
                    validPriceCount++;
                }
            }
        }

        if(validPriceCount == 0) {
            return ( false, 0);
        }

        if(validPriceCount == 1) {
            return ( true, prices[0]);
        }

        // Calculate median
        for(uint256 i = 0; i < validPriceCount; i++)
            for(uint256 j = 0; j < validPriceCount - i - 1; j++)
            {
                if (prices[j] > prices[j + 1]) {
                    (prices[j], prices[j + 1]) = (prices[j + 1], prices[j]);
                }
            }

        if (validPriceCount % 2 == 0) {
            return ( true, (prices[validPriceCount / 2 - 1] + prices[validPriceCount / 2]) / 2);
        }

        return ( true, prices[validPriceCount / 2]);
    }

    /// @notice Check if circuit breaker is currently active
    /// @dev Circuit breaker auto-resets after cooldown period
    /// @return True if circuit breaker is active
    function _isCircuitBroken() internal view returns (bool) {
        return (circuitBroken && block.timestamp < circuitBrokenAt + circuitBreakerCooldown);
    }

    /// @notice Add an oracle to the array
    /// @dev Internal function called by addChainLinkOracle and addUniswapTwap
    /// @param oracle_ Oracle/pool address
    /// @param decimals_ Price decimals
    /// @param stalenessThreshold Max age of price data
    /// @param oracleType Type of oracle (CHAINLINK or UNISWAP_TWAP)
    /// @param isToken0Stablecoin_ Whether token0 is the stablecoin (for Uniswap)
    function _addOracle(
        address oracle_,
        uint8 decimals_,
        uint256 stalenessThreshold,
        OracleType oracleType,
        bool isToken0Stablecoin_) internal
    {
        oracles.push(OracleData({
            oracle            : oracle_,
            stalenessThreshold       : stalenessThreshold,
            decimals          : decimals_,
            isActive          : true,
            oracleType        : oracleType,
            isToken0Stablecoin : isToken0Stablecoin_
        }));

        emit OracleActivated(oracles.length - 1, oracle_, oracleType);
    }

    /// @notice Authorize contract upgrade
    /// @dev Only UPGRADER_ROLE can upgrade
    /// @param newImplementation Address of new implementation
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(UPGRADER_ROLE) {}
}
