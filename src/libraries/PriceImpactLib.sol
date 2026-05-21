// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/AggregatorV3Interface.sol";

/**
 * @title PriceImpactLib
 * @notice Library for calculating price impact in token swaps
 * @dev Used to determine if a swap will have excessive price impact
 * 
 * Price impact is the percentage difference between:
 * - Execution price (actual price paid in the swap)
 * - Spot price (fair market price from oracle or reference)
 * 
 * High price impact indicates:
 * - Low liquidity in the pool
 * - Large swap size relative to pool
 * - Potential slippage losses for user
 */
library PriceImpactLib {
    // ============ Constants ============

    /// @notice Basis points denominator (100% = 10000 bps)
    uint256 constant BPS_DENOMINATOR = 10000;

    /// @notice Maximum acceptable price impact (5% = 500 bps)
    uint256 constant MAX_ACCEPTABLE_IMPACT_BPS = 500;

    /// @notice Warning threshold (2% = 200 bps)
    uint256 constant WARNING_IMPACT_BPS = 200;

    // ============ Structs ============

    /**
     * @notice Price impact calculation result
     * @param impactBps Price impact in basis points
     * @param executionPrice Actual execution price (scaled)
     * @param spotPrice Reference spot price (scaled)
     * @param isAcceptable Whether impact is within acceptable range
     */
    struct PriceImpactResult {
        uint256 impactBps;
        uint256 executionPrice;
        uint256 spotPrice;
        bool isAcceptable;
    }

    /**
     * @notice Token price data
     * @param price Price scaled to 18 decimals
     * @param timestamp Price timestamp
     * @param source Price source identifier
     */
    struct TokenPrice {
        uint256 price;
        uint256 timestamp;
        string source;
    }

    // ============ Errors ============

    error InvalidAmount();
    error InvalidPrice();
    error DivisionByZero();
    error PriceTooStale();

    // ============ Main Functions ============

    /**
     * @notice Calculate price impact for a swap
     * @dev Compares execution price with spot price
     * @param amountIn Input token amount
     * @param amountOut Output token amount
     * @param tokenInDecimals Input token decimals
     * @param tokenOutDecimals Output token decimals
     * @param spotPrice Spot price (scaled to 18 decimals)
     * @return result Price impact calculation result
     */
    function calculatePriceImpact(
        uint256 amountIn,
        uint256 amountOut,
        uint8 tokenInDecimals,
        uint8 tokenOutDecimals,
        uint256 spotPrice
    ) internal pure returns (PriceImpactResult memory result) {
        if (amountIn == 0 || amountOut == 0) {
            revert InvalidAmount();
        }
        if (spotPrice == 0) {
            revert InvalidPrice();
        }

        // Calculate execution price: (amountOut / amountIn) * (10^18)
        // Scaled to 18 decimals for precision
        uint256 executionPrice = _calculateExecutionPrice(
            amountIn,
            amountOut,
            tokenInDecimals,
            tokenOutDecimals
        );

        result.executionPrice = executionPrice;
        result.spotPrice = spotPrice;

        // Calculate price impact in basis points
        // Impact = ((spotPrice - executionPrice) / spotPrice) * 10000
        if (executionPrice >= spotPrice) {
            // No impact or positive slippage
            result.impactBps = 0;
        } else {
            uint256 priceDiff = spotPrice - executionPrice;
            result.impactBps = (priceDiff * BPS_DENOMINATOR) / spotPrice;
        }

        // Check if impact is acceptable
        result.isAcceptable = result.impactBps <= MAX_ACCEPTABLE_IMPACT_BPS;
    }

    /**
     * @notice Calculate price impact with Chainlink oracle price
     * @dev Fetches spot price from Chainlink aggregator
     * @param amountIn Input token amount
     * @param amountOut Output token amount
     * @param tokenInDecimals Input token decimals
     * @param tokenOutDecimals Output token decimals
     * @param priceFeed Chainlink price feed address
     * @param maxStaleness Maximum acceptable price staleness (seconds)
     * @return result Price impact calculation result
     */
    function calculatePriceImpactWithOracle(
        uint256 amountIn,
        uint256 amountOut,
        uint8 tokenInDecimals,
        uint8 tokenOutDecimals,
        address priceFeed,
        uint256 maxStaleness
    ) internal view returns (PriceImpactResult memory result) {
        // Get spot price from Chainlink
        (, int256 price, , uint256 updatedAt, ) = AggregatorV3Interface(priceFeed).latestRoundData();
        
        if (price <= 0) {
            revert InvalidPrice();
        }
        if (block.timestamp - updatedAt > maxStaleness) {
            revert PriceTooStale();
        }

        uint256 spotPrice = uint256(price);
        
        return calculatePriceImpact(
            amountIn,
            amountOut,
            tokenInDecimals,
            tokenOutDecimals,
            spotPrice
        );
    }

    /**
     * @notice Calculate execution price from swap amounts
     * @dev Normalizes prices to 18 decimals for comparison
     * @param amountIn Input token amount (atomic)
     * @param amountOut Output token amount (atomic)
     * @param tokenInDecimals Input token decimals
     * @param tokenOutDecimals Output token decimals
     * @return executionPrice Price scaled to 18 decimals
     */
    function _calculateExecutionPrice(
        uint256 amountIn,
        uint256 amountOut,
        uint8 tokenInDecimals,
        uint8 tokenOutDecimals
    ) internal pure returns (uint256 executionPrice) {
        // Normalize to 18 decimals
        // executionPrice = (amountOut * 10^18 * 10^tokenInDecimals) / (amountIn * 10^tokenOutDecimals)
        
        uint256 scalingFactor = 10**(18 + tokenInDecimals - tokenOutDecimals);
        
        if (amountIn == 0) {
            revert DivisionByZero();
        }
        
        executionPrice = (amountOut * scalingFactor) / amountIn;
    }

    /**
     * @notice Check if price impact is acceptable
     * @dev Simple boolean check
     * @param impactBps Price impact in basis points
     * @return isAcceptable Whether impact is acceptable
     */
    function isImpactAcceptable(uint256 impactBps) internal pure returns (bool isAcceptable) {
        return impactBps <= MAX_ACCEPTABLE_IMPACT_BPS;
    }

    /**
     * @notice Get price impact warning level
     * @dev Returns warning level based on impact
     * @param impactBps Price impact in basis points
     * @return warningLevel 0=none, 1=warning, 2=critical
     */
    function getImpactWarningLevel(uint256 impactBps) internal pure returns (uint8 warningLevel) {
        if (impactBps <= WARNING_IMPACT_BPS) {
            return 0; // No warning
        } else if (impactBps <= MAX_ACCEPTABLE_IMPACT_BPS) {
            return 1; // Warning
        } else {
            return 2; // Critical
        }
    }

    /**
     * @notice Calculate minimum output amount with slippage protection
     * @dev Applies slippage tolerance to expected output
     * @param expectedOut Expected output amount
     * @param slippageBps Slippage tolerance in basis points
     * @return minOut Minimum acceptable output
     */
    function calculateMinOutput(uint256 expectedOut, uint256 slippageBps) 
        internal pure returns (uint256 minOut) 
    {
        if (slippageBps > BPS_DENOMINATOR) {
            revert InvalidAmount();
        }
        
        minOut = (expectedOut * (BPS_DENOMINATOR - slippageBps)) / BPS_DENOMINATOR;
    }

    /**
     * @notice Calculate optimal split ratio for multi-path swap
     * @dev Determines how to split a swap across multiple paths
     * @param amountIn Total input amount
     * @param path1Capacity Estimated capacity of path 1
     * @param path2Capacity Estimated capacity of path 2
     * @return split1 Amount to route through path 1
     * @return split2 Amount to route through path 2
     */
    function calculateOptimalSplit(
        uint256 amountIn,
        uint256 path1Capacity,
        uint256 path2Capacity
    ) internal pure returns (uint256 split1, uint256 split2) {
        uint256 totalCapacity = path1Capacity + path2Capacity;
        
        if (totalCapacity == 0) {
            // Equal split if no capacity info
            split1 = amountIn / 2;
            split2 = amountIn - split1;
            return (split1, split2);
        }
        
        // Split proportionally to capacity
        split1 = (amountIn * path1Capacity) / totalCapacity;
        split2 = amountIn - split1;
    }

    /**
     * @notice Estimate price impact from pool liquidity
     * @dev Rough estimate based on swap size vs pool liquidity
     * @param amountIn Input amount
     * @param poolLiquidity Total pool liquidity (in output token)
     * @return estimatedImpactBps Estimated impact in basis points
     */
    function estimateImpactFromLiquidity(
        uint256 amountIn,
        uint256 poolLiquidity
    ) internal pure returns (uint256 estimatedImpactBps) {
        if (poolLiquidity == 0) {
            return type(uint256).max; // Infinite impact
        }
        
        // Simple linear model: impact = (amountIn / poolLiquidity) * 100%
        // In practice, AMM impact is quadratic, but this is a conservative estimate
        estimatedImpactBps = (amountIn * BPS_DENOMINATOR * 100) / poolLiquidity;
    }
}
