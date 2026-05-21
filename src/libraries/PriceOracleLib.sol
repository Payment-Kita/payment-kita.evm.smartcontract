// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/AggregatorV3Interface.sol";

/**
 * @title PriceOracleLib
 * @notice Library for fetching prices from Chainlink oracles
 * @dev Provides price validation and impact calculation
 * 
 * Supported Chains:
 * - Ethereum Mainnet
 * - Base
 * - Polygon
 * - BSC
 * - Arbitrum
 */
library PriceOracleLib {
    // ============ Structs ============
    
    /**
     * @notice Price data structure
     * @param price Price scaled to 8 decimals (Chainlink standard)
     * @param updatedAt Last update timestamp
     * @param roundId Chainlink round ID
     * @param stale Whether the price is stale
     */
    struct PriceData {
        int256 price;
        uint256 updatedAt;
        uint80 roundId;
        bool stale;
    }
    
    /**
     * @notice Oracle configuration
     * @param aggregator Chainlink aggregator address
     * @param maxStaleness Maximum acceptable price age in seconds
     * @param minAnswer Minimum acceptable price (prevent manipulation)
     * @param maxAnswer Maximum acceptable price (prevent manipulation)
     */
    struct OracleConfig {
        address aggregator;
        uint256 maxStaleness;
        int256 minAnswer;
        int256 maxAnswer;
    }

    // ============ Constants ============
    
    /// @notice Maximum staleness: 1 hour (3600 seconds)
    uint256 constant DEFAULT_MAX_STALENESS = 3600;
    
    /// @notice Chainlink price decimals
    uint8 constant CHAINLINK_DECIMALS = 8;

    // ============ Main Functions ============
    
    /**
     * @notice Fetch latest price from Chainlink oracle
     * @dev Includes staleness and sanity checks
     * @param config Oracle configuration
     * @return data Price data structure
     */
    function getLatestPrice(OracleConfig memory config) 
        internal view returns (PriceData memory data) 
    {
        if (config.aggregator == address(0)) {
            data.stale = true;
            return data;
        }
        
        AggregatorV3Interface aggregator = AggregatorV3Interface(config.aggregator);
        
        try aggregator.latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            data.price = answer;
            data.updatedAt = updatedAt;
            data.roundId = roundId;
            
            // Check staleness
            if (block.timestamp - updatedAt > config.maxStaleness) {
                data.stale = true;
            }
            
            // Sanity checks
            if (answer < config.minAnswer || answer > config.maxAnswer) {
                data.stale = true;
            }
            
            // Check answer is positive
            if (answer <= 0) {
                data.stale = true;
            }
        } catch {
            data.stale = true;
        }
        
        return data;
    }
    
    /**
     * @notice Get price with custom staleness
     * @dev Convenience function with default sanity bounds
     * @param aggregator Chainlink aggregator address
     * @param maxStaleness Maximum price age in seconds
     * @return data Price data
     */
    function getPriceWithStaleness(address aggregator, uint256 maxStaleness)
        internal view returns (PriceData memory data)
    {
        OracleConfig memory config = OracleConfig({
            aggregator: aggregator,
            maxStaleness: maxStaleness,
            minAnswer: 0,
            maxAnswer: type(int256).max
        });
        
        return getLatestPrice(config);
    }
    
    /**
     * @notice Calculate fair price from multiple oracles
     * @dev Averages prices from multiple sources
     * @param aggregators Array of aggregator addresses
     * @return fairPrice Average price
     * @return isReliable Whether the price is reliable
     */
    function getFairPrice(address[] memory aggregators)
        internal view returns (int256 fairPrice, bool isReliable)
    {
        if (aggregators.length == 0) {
            return (0, false);
        }
        
        int256 totalPrice = 0;
        uint256 validCount = 0;
        
        for (uint256 i = 0; i < aggregators.length; i++) {
            OracleConfig memory config = OracleConfig({
                aggregator: aggregators[i],
                maxStaleness: DEFAULT_MAX_STALENESS,
                minAnswer: 0,
                maxAnswer: type(int256).max
            });
            
            PriceData memory data = getLatestPrice(config);
            
            if (!data.stale && data.price > 0) {
                totalPrice += data.price;
                validCount++;
            }
        }
        
        if (validCount == 0) {
            return (0, false);
        }
        
        fairPrice = totalPrice / int256(validCount);
        isReliable = validCount >= aggregators.length / 2;
        
        return (fairPrice, isReliable);
    }
    
    /**
     * @notice Validate price deviation
     * @dev Checks if price deviates too much from oracle
     * @param executionPrice Execution price from DEX
     * @param oraclePrice Reference price from oracle
     * @param maxDeviationBps Maximum acceptable deviation in bps
     * @return isValid Whether price is within acceptable range
     * @return deviationBps Actual deviation in bps
     */
    function validatePriceDeviation(
        uint256 executionPrice,
        uint256 oraclePrice,
        uint256 maxDeviationBps
    ) internal pure returns (bool isValid, uint256 deviationBps) {
        if (oraclePrice == 0) {
            return (false, 0);
        }
        
        // Calculate deviation
        if (executionPrice > oraclePrice) {
            deviationBps = ((executionPrice - oraclePrice) * 10000) / oraclePrice;
        } else {
            deviationBps = ((oraclePrice - executionPrice) * 10000) / oraclePrice;
        }
        
        isValid = deviationBps <= maxDeviationBps;
        
        return (isValid, deviationBps);
    }
    
    /**
     * @notice Convert Chainlink price to custom decimals
     * @dev Adjusts price from 8 decimals to target decimals
     * @param chainlinkPrice Price in Chainlink format (8 decimals)
     * @param targetDecimals Target decimal places
     * @return convertedPrice Price in target decimals
     */
    function convertPriceDecimals(int256 chainlinkPrice, uint8 targetDecimals)
        internal pure returns (uint256 convertedPrice)
    {
        if (chainlinkPrice <= 0) {
            return 0;
        }
        
        uint256 price = uint256(chainlinkPrice);
        
        if (targetDecimals > CHAINLINK_DECIMALS) {
            // Scale up
            uint256 multiplier = 10**(targetDecimals - CHAINLINK_DECIMALS);
            convertedPrice = price * multiplier;
        } else if (targetDecimals < CHAINLINK_DECIMALS) {
            // Scale down
            uint256 divisor = 10**(CHAINLINK_DECIMALS - targetDecimals);
            convertedPrice = price / divisor;
        } else {
            convertedPrice = price;
        }
        
        return convertedPrice;
    }
}
