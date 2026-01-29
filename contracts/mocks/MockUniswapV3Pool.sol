// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockUniswapV3Pool
 * @notice Simulated Uniswap V3 pool for TWAP testing
 */
contract MockUniswapV3Pool {
    address public immutable token0;
    address public immutable token1;
    
    int24 public currentTick;
    uint160 public sqrtPriceX96;
    
    struct Observation {
        uint32 blockTimestamp;
        int56 tickCumulative;
        uint160 secondsPerLiquidityCumulativeX128;
        bool initialized;
    }
    
    Observation[65536] public observations;
    uint16 public observationIndex;
    uint16 public observationCardinality;
    uint16 public observationCardinalityNext;
    
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(
        address _token0,
        address _token1,
        int24 _initialTick
    ) {
        require(_token0 < _token1, "Token order");
        
        token0 = _token0;
        token1 = _token1;
        currentTick = _initialTick;
        sqrtPriceX96 = _getSqrtRatioAtTick(_initialTick);
        owner = msg.sender;
        
        // Initialize first observation with CURRENT block.timestamp
        observations[0] = Observation({
            blockTimestamp: uint32(block.timestamp),
            tickCumulative: 0,
            secondsPerLiquidityCumulativeX128: 0,
            initialized: true
        });
        observationCardinality = 1;
        observationCardinalityNext = 100; // Pre-allocate space
    }

    /// @notice Write new observation using CURRENT block.timestamp
    /// @dev Call this after_ using networkHelpers.time.increase()
    function writeObservation() external {
        Observation memory last = observations[observationIndex];
        
        // Calculate time delta from last observation
        uint32 timeElapsed = uint32(block.timestamp) - last.blockTimestamp;
        
        if (timeElapsed == 0) return; // No time passed
        
        // Accumulate ticks
        int56 tickCumulative = last.tickCumulative + int56(currentTick) * int56(uint56(timeElapsed));
        
        // Write new observation
        uint16 newIndex = (observationIndex + 1) % observationCardinalityNext;
        observations[newIndex] = Observation({
            blockTimestamp: uint32(block.timestamp),
            tickCumulative: tickCumulative,
            secondsPerLiquidityCumulativeX128: 0,
            initialized: true
        });
        
        observationIndex = newIndex;
        if (observationCardinality < observationCardinalityNext) {
            observationCardinality++;
        }
    }

    /// @notice Set tick and write observation
    function setTickAndObserve(int24 newTick) external onlyOwner {
        // First write observation with OLD tick
        this.writeObservation();
        
        // Then update tick
        currentTick = newTick;
        sqrtPriceX96 = _getSqrtRatioAtTick(newTick);
    }

    function slot0() external view returns (
        uint160, int24, uint16, uint16, uint16, uint8, bool
    ) {
        return (
            sqrtPriceX96,
            currentTick,
            observationIndex,
            observationCardinality,
            observationCardinalityNext,
            0,
            true
        );
    }

    function observe(uint32[] calldata secondsAgos) 
        external 
        view 
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) 
    {
        tickCumulatives = new int56[](secondsAgos.length);
        secondsPerLiquidityCumulativeX128s = new uint160[](secondsAgos.length);
        
        for (uint256 i = 0; i < secondsAgos.length; i++) {
            tickCumulatives[i] = _getTickCumulativeAtTime(secondsAgos[i]);
        }
    }

    function _getTickCumulativeAtTime(uint32 secondsAgo) internal view returns (int56) {
        uint32 targetTime = uint32(block.timestamp) - secondsAgo;
        Observation memory latest = observations[observationIndex];
        
        if (secondsAgo == 0) {
            // Current time - extrapolate from latest
            uint32 timeDelta = uint32(block.timestamp) - latest.blockTimestamp;
            return latest.tickCumulative + int56(currentTick) * int56(uint56(timeDelta));
        }
        
        // Find observations around targetTime
        // Simple approach: find the two observations bracketing targetTime
        Observation memory before;
        Observation memory after_;
        bool foundBefore = false;
        bool foundAfter = false;
        
        for (uint16 i = 0; i < observationCardinality; i++) {
            Observation memory obs = observations[i];
            if (!obs.initialized) continue;
            
            if (obs.blockTimestamp <= targetTime) {
                if (!foundBefore || obs.blockTimestamp > before.blockTimestamp) {
                    before = obs;
                    foundBefore = true;
                }
            }
            if (obs.blockTimestamp > targetTime) {
                if (!foundAfter || obs.blockTimestamp < after_.blockTimestamp) {
                    after_ = obs;
                    foundAfter = true;
                }
            }
        }
        
        if (!foundBefore) {
            // Target is before all observations - use first observation
            return observations[0].tickCumulative;
        }
        
        if (!foundAfter) {
            // Target is after_ all observations - extrapolate from latest
            uint32 timeDelta = targetTime - before.blockTimestamp;
            return before.tickCumulative + int56(currentTick) * int56(uint56(timeDelta));
        }
        
        // Interpolate between before and after_
        uint32 totalTime = after_.blockTimestamp - before.blockTimestamp;
        uint32 deltaTime = targetTime - before.blockTimestamp;
        int56 tickDelta = after_.tickCumulative - before.tickCumulative;
        
        return before.tickCumulative + (tickDelta * int56(uint56(deltaTime))) / int56(uint56(totalTime));
    }

    function _getSqrtRatioAtTick(int24 tick) internal pure returns (uint160) {
        uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));
        require(absTick <= 887272, "T");

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

        return uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    }

    function tickSpacing() external pure returns (int24) {
        return 60;
    }
}