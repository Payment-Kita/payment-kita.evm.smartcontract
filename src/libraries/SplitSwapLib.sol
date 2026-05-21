// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SplitSwapLib
 * @notice Library for optimal split-swap routing across multiple DEXes
 * @dev Calculates optimal split ratios to minimize price impact
 * 
 * Features:
 * - Split swaps across OKX DEX + Uniswap for better rates
 * - Dynamic ratio calculation based on liquidity
 * - Price impact optimization
 * - Multi-path execution
 */
library SplitSwapLib {
    // ============ Constants ============
    
    /// @notice Basis points denominator (100% = 10000 bps)
    uint256 constant BPS_DENOMINATOR = 10000;
    
    /// @notice Maximum number of split paths
    uint256 constant MAX_SPLIT_PATHS = 4;
    
    /// @notice Minimum split percentage (1% = 100 bps)
    uint256 constant MIN_SPLIT_BPS = 100;

    // ============ Structs ============
    
    /**
     * @notice Split path configuration
     * @param dex DEX identifier (0=OKX, 1=UniswapV4, 2=UniswapV3, 3=UniswapV2)
     * @param percentageBps Percentage of total amount to route through this path (in bps)
     * @param expectedOut Expected output amount from this path
     * @param priceImpactBps Price impact for this path (in bps)
     */
    struct SplitPath {
        uint8 dex;
        uint256 percentageBps;
        uint256 expectedOut;
        uint256 priceImpactBps;
    }
    
    /**
     * @notice Split swap result
     * @param paths Array of split paths
     * @param totalExpectedOut Total expected output from all paths
     * @param totalPriceImpactBps Weighted average price impact
     * @param gasEstimate Total gas estimate for all paths
     */
    struct SplitResult {
        SplitPath[] paths;
        uint256 totalExpectedOut;
        uint256 totalPriceImpactBps;
        uint256 gasEstimate;
    }
    
    /**
     * @notice Liquidity info for a DEX
     * @param available Whether the DEX has liquidity for this pair
     * @param liquidityBps Available liquidity relative to swap size (in bps)
     * @param priceImpactBps Estimated price impact for full swap
     */
    struct LiquidityInfo {
        bool available;
        uint256 liquidityBps;
        uint256 priceImpactBps;
    }

    // ============ Main Functions ============
    
    /**
     * @notice Calculate optimal split for a swap across multiple DEXes
     * @dev Analyzes liquidity and price impact to determine best split ratio
     * @param amountIn Total input amount
     * @param liquidityInfos Liquidity info for each DEX [OKX, V4, V3, V2]
     * @return result Optimal split result
     */
    function calculateOptimalSplit(
        uint256 amountIn,
        LiquidityInfo[4] memory liquidityInfos
    ) internal pure returns (SplitResult memory result) {
        result.paths = new SplitPath[](0);
        result.totalExpectedOut = 0;
        result.totalPriceImpactBps = 0;
        result.gasEstimate = 0;
        
        // Count available DEXes
        uint256 availableCount = 0;
        for (uint256 i = 0; i < 4; i++) {
            if (liquidityInfos[i].available) {
                availableCount++;
            }
        }
        
        if (availableCount == 0) {
            return result; // No liquidity available
        }
        
        // Single DEX has sufficient liquidity - use it
        if (availableCount == 1) {
            for (uint256 i = 0; i < 4; i++) {
                if (liquidityInfos[i].available) {
                    result.paths = new SplitPath[](1);
                    result.paths[0] = SplitPath({
                        dex: uint8(i),
                        percentageBps: BPS_DENOMINATOR,
                        expectedOut: 0, // Will be calculated during execution
                        priceImpactBps: liquidityInfos[i].priceImpactBps
                    });
                    result.totalPriceImpactBps = liquidityInfos[i].priceImpactBps;
                    result.gasEstimate = _estimateGasForPath(1);
                    return result;
                }
            }
        }
        
        // Multiple DEXes available - calculate optimal split
        uint256 totalWeight = 0;
        uint256[] memory weights = new uint256[](4);
        
        // Calculate weights based on liquidity and price impact
        for (uint256 i = 0; i < 4; i++) {
            if (liquidityInfos[i].available) {
                // Higher weight for lower price impact
                uint256 impactFactor = BPS_DENOMINATOR - liquidityInfos[i].priceImpactBps;
                if (impactFactor > BPS_DENOMINATOR) {
                    impactFactor = BPS_DENOMINATOR;
                }
                
                // Weight = liquidity * (1 - priceImpact)
                weights[i] = (liquidityInfos[i].liquidityBps * impactFactor) / BPS_DENOMINATOR;
                totalWeight += weights[i];
            }
        }
        
        // Calculate split percentages
        uint256 remainingBps = BPS_DENOMINATOR;
        for (uint256 i = 0; i < 4; i++) {
            if (liquidityInfos[i].available && totalWeight > 0) {
                uint256 percentageBps = (weights[i] * BPS_DENOMINATOR) / totalWeight;
                
                // Ensure minimum split percentage
                if (percentageBps < MIN_SPLIT_BPS) {
                    percentageBps = 0;
                }
                
                // Last DEX gets remaining percentage
                if (i == 3 || percentageBps > remainingBps) {
                    percentageBps = remainingBps;
                }
                
                if (percentageBps > 0) {
                    result.paths = arrayPush(result.paths, SplitPath({
                        dex: uint8(i),
                        percentageBps: percentageBps,
                        expectedOut: 0,
                        priceImpactBps: liquidityInfos[i].priceImpactBps
                    }));
                    remainingBps -= percentageBps;
                    
                    // Weighted price impact
                    result.totalPriceImpactBps += (percentageBps * liquidityInfos[i].priceImpactBps) / BPS_DENOMINATOR;
                }
            }
        }
        
        // Gas estimate based on number of paths
        result.gasEstimate = _estimateGasForPath(result.paths.length);
        
        return result;
    }
    
    /**
     * @notice Calculate amount to route through each path
     * @dev Splits input amount according to split percentages
     * @param amountIn Total input amount
     * @param paths Split paths with percentages
     * @return amounts Array of amounts for each path
     */
    function calculateSplitAmounts(
        uint256 amountIn,
        SplitPath[] memory paths
    ) internal pure returns (uint256[] memory amounts) {
        amounts = new uint256[](paths.length);
        uint256 totalAllocated = 0;
        
        for (uint256 i = 0; i < paths.length; i++) {
            if (i == paths.length - 1) {
                // Last path gets remaining amount
                amounts[i] = amountIn - totalAllocated;
            } else {
                amounts[i] = (amountIn * paths[i].percentageBps) / BPS_DENOMINATOR;
                totalAllocated += amounts[i];
            }
        }
        
        return amounts;
    }
    
    /**
     * @notice Compare split vs single-path execution
     * @dev Determines if split routing provides better rate
     * @param singlePathOut Expected output from single best path
     * @param splitResult Split routing result
     * @return isBetter Whether split routing is better
     * @return improvementBps Improvement in basis points
     */
    function compareSplitVsSingle(
        uint256 singlePathOut,
        SplitResult memory splitResult
    ) internal pure returns (bool isBetter, uint256 improvementBps) {
        if (singlePathOut == 0 || splitResult.totalExpectedOut == 0) {
            return (false, 0);
        }
        
        if (splitResult.totalExpectedOut > singlePathOut) {
            isBetter = true;
            uint256 diff = splitResult.totalExpectedOut - singlePathOut;
            improvementBps = (diff * BPS_DENOMINATOR) / singlePathOut;
        } else {
            isBetter = false;
            improvementBps = 0;
        }
        
        return (isBetter, improvementBps);
    }
    
    /**
     * @notice Estimate price impact for a swap
     * @dev Simple linear model: impact = (amount / liquidity) * 100%
     * @param amountIn Swap amount
     * @param liquidity Available liquidity
     * @return impactBps Price impact in basis points
     */
    function estimatePriceImpact(
        uint256 amountIn,
        uint256 liquidity
    ) internal pure returns (uint256 impactBps) {
        if (liquidity == 0) {
            return type(uint256).max; // Infinite impact
        }
        
        // Linear model with 2x multiplier for safety margin
        impactBps = (amountIn * BPS_DENOMINATOR * 2) / liquidity;
        
        // Cap at 100% (10000 bps)
        if (impactBps > BPS_DENOMINATOR) {
            impactBps = BPS_DENOMINATOR;
        }
        
        return impactBps;
    }

    // ============ Internal Functions ============
    
    /**
     * @notice Estimate gas for split swap execution
     * @dev Rough estimate based on number of paths
     * @param pathCount Number of split paths
     * @return gasEstimate Estimated gas units
     */
    function _estimateGasForPath(uint256 pathCount) internal pure returns (uint256 gasEstimate) {
        // Base gas + per-path gas
        gasEstimate = 100_000 + (pathCount * 150_000);
    }
    
    /**
     * @notice Push SplitPath to array
     * @dev Helper function for dynamic array manipulation
     */
    function arrayPush(SplitPath[] memory paths, SplitPath memory path) 
        internal pure returns (SplitPath[] memory) 
    {
        SplitPath[] memory newPaths = new SplitPath[](paths.length + 1);
        for (uint256 i = 0; i < paths.length; i++) {
            newPaths[i] = paths[i];
        }
        newPaths[paths.length] = path;
        return newPaths;
    }
}
