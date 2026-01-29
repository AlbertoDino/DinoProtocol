// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockChainlinkAggregator
 * @notice Controllable price feed for testing
 */
contract MockChainlinkAggregator {
    string public description = "ETH / USD";
    uint8 public decimals = 8;
    uint256 public version = 1;
    
    int256 private _price;
    uint256 private _updatedAt;
    uint80 private _roundId;
    
    address public owner;
    
    event PriceUpdated(int256 oldPrice, int256 newPrice, uint80 roundId);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(int256 initialPrice) {
        owner = msg.sender;
        _price = initialPrice;
        _updatedAt = block.timestamp;
        _roundId = 1;
    }

    /// @notice Set new price (only owner)
    function setPrice(int256 newPrice) external onlyOwner {
        int256 oldPrice = _price;
        _price = newPrice;
        _updatedAt = block.timestamp;
        _roundId++;
        emit PriceUpdated(oldPrice, newPrice, _roundId);
    }

    /// @notice Refresh timestamp without changing price
    function refreshTimestamp() external {
        _updatedAt = block.timestamp;
    }

    /// @notice Simulate price movement (for testing scenarios)
    function adjustPrice(int256 percentChange) external onlyOwner {
        // percentChange: 100 = +1%, -100 = -1%, 1000 = +10%
        int256 oldPrice = _price;
        _price = _price * (10000 + percentChange) / 10000;
        _updatedAt = block.timestamp;
        _roundId++;
        emit PriceUpdated(oldPrice, _price, _roundId);
    }

    /// @notice Chainlink interface
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (
            _roundId,
            _price,
            _updatedAt,
            _updatedAt,
            _roundId
        );
    }

    /// @notice Get specific round (returns same as latest for mock)
    function getRoundData(uint80) external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (
            _roundId,
            _price,
            _updatedAt,
            _updatedAt,
            _roundId
        );
    }

    /// @notice Transfer ownership
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
}