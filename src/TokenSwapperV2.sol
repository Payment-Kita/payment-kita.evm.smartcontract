// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./TokenSwapper.sol";
import "./integrations/okx/IOKXRouter.sol";
import "./integrations/okx/OKXDexAdapter.sol";
import "./libraries/PriceImpactLib.sol";

/**
 * @title TokenSwapperV2
 * @notice Enhanced TokenSwapper with OKX DEX integration for better liquidity
 * @dev Extends TokenSwapper with OKX DEX as primary liquidity source
 * 
 * Fallback Chain:
 * 1. ✅ OKX DEX (PRIMARY - aggregated liquidity)
 * 2. ⚠️ Uniswap V4 (FALLBACK 1 - direct pools)
 * 3. ⚠️ Uniswap V3 (FALLBACK 2 - registered pools)
 * 4. ⚠️ Uniswap V2 (FALLBACK 3 - legacy pools)
 * 5. ❌ Simulation (LAST RESORT - 1:1 placeholder)
 * 
 * Key Features:
 * - OKX DEX integration for better stablecoin rates
 * - Automatic fallback to Uniswap if OKX unavailable
 * - Price impact validation
 * - Split routing support (future enhancement)
 * - Event logging for monitoring
 */
contract TokenSwapperV2 is TokenSwapper {
    using PriceImpactLib for uint256;
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    /// @notice OKX DEX Adapter address
    address public okxDexAdapter;

    /// @notice Whether OKX integration is enabled
    bool public okxIntegrationEnabled;

    /// @notice Maximum acceptable price impact in basis points (500 = 5%)
    uint256 public okxMaxPriceImpactBps;

    /// @notice Last quote source used
    LiquiditySource internal _lastQuoteSource;

    /// @notice Quote cache (address => amount => quote => timestamp)
    mapping(address => mapping(uint256 => mapping(uint256 => QuoteCache))) public quoteCache;

    /// @notice Quote cache validity period (in blocks)
    uint256 public quoteCacheValidityBlocks;

    // ============ Enums ============

    /**
     * @notice Liquidity source enumeration
     */
    enum LiquiditySource {
        OKX_DEX,       // ✅ Priority 1 - Aggregated liquidity
        UNISWAP_V4,    // ⚠️ Priority 2 - Direct V4 pools
        UNISWAP_V3,    // ⚠️ Priority 3 - Registered V3 pools
        UNISWAP_V2,    // ⚠️ Priority 4 - Legacy V2 pools
        SIMULATION     // ❌ Priority 5 - Last resort (1:1)
    }

    /**
     * @notice Quote cache structure
     */
    struct QuoteCache {
        uint256 amountOut;
        uint256 timestamp;
        LiquiditySource source;
        bool valid;
    }

    // ============ Events ============

    event OKXDexAdapterUpdated(address indexed oldAdapter, address indexed newAdapter);
    event OKXIntegrationEnabled(bool enabled);
    event MaxPriceImpactUpdated(uint256 newMaxImpactBps);
    event LiquiditySourceSelected(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        LiquiditySource source,
        uint256 amountOut,
        uint256 timestamp
    );
    event PriceImpactWarning(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 impactBps,
        bool isAcceptable
    );
    event QuoteCached(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        LiquiditySource source
    );

    // ============ Errors ============

    error InvalidOKXAdapter();
    error OKXIntegrationDisabled();
    error PriceImpactTooHigh(uint256 impactBps, uint256 maxBps);
    error QuoteCacheExpired();
    error NoLiquiditySourceAvailable();

    // ============ Constructor ============

    /**
     * @notice Initialize TokenSwapperV2
     * @param _universalRouter Uniswap V4 Universal Router address
     * @param _poolManager Uniswap V4 PoolManager address
     * @param _bridgeToken Bridge token address (e.g., USDC)
     * @param _okxAdapter OKX DEX Adapter address
     */
    constructor(
        address _universalRouter,
        address _poolManager,
        address _bridgeToken,
        address _okxAdapter
    ) TokenSwapper(_universalRouter, _poolManager, _bridgeToken) {
        if (_okxAdapter == address(0)) {
            revert InvalidOKXAdapter();
        }
        
        okxDexAdapter = _okxAdapter;
        okxIntegrationEnabled = true;
        okxMaxPriceImpactBps = 500; // 5% default
        quoteCacheValidityBlocks = 2; // ~24 seconds on most chains
        
        emit OKXDexAdapterUpdated(address(0), _okxAdapter);
        emit OKXIntegrationEnabled(true);
        emit MaxPriceImpactUpdated(500);
    }

    // ============ Admin Functions ============

    /**
     * @notice Update OKX DEX Adapter address
     * @param _newAdapter New OKX Adapter address
     */
    function setOKXDexAdapter(address _newAdapter) external onlyOwner {
        if (_newAdapter == address(0)) {
            revert InvalidOKXAdapter();
        }
        address oldAdapter = okxDexAdapter;
        okxDexAdapter = _newAdapter;
        emit OKXDexAdapterUpdated(oldAdapter, _newAdapter);
    }

    /**
     * @notice Enable or disable OKX integration
     * @param _enabled Whether to enable integration
     */
    function setOKXIntegrationEnabled(bool _enabled) external onlyOwner {
        okxIntegrationEnabled = _enabled;
        emit OKXIntegrationEnabled(_enabled);
    }

    /**
     * @notice Update maximum acceptable price impact
     * @param _maxImpactBps New maximum impact in basis points
     */
    function setMaxPriceImpactBps(uint256 _maxImpactBps) external onlyOwner {
        require(_maxImpactBps <= 1000, "Max 10% impact"); // Max 10%
        okxMaxPriceImpactBps = _maxImpactBps;
        emit MaxPriceImpactUpdated(_maxImpactBps);
    }

    /**
     * @notice Set quote cache validity period
     * @param _blocks Validity period in blocks
     */
    function setQuoteCacheValidityBlocks(uint256 _blocks) external onlyOwner {
        quoteCacheValidityBlocks = _blocks;
    }

    /**
     * @notice Clear quote cache for a specific pair
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     */
    function clearQuoteCache(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external {
        delete quoteCache[tokenIn][amountIn][uint256(uint160(tokenOut))];
    }

    // ============ Override Core Functions ============

    /**
     * @notice Get real quote with OKX DEX integration
     * @dev Implements full fallback chain: OKX → V4 → V3 → V2 → Simulation
     * @param tokenIn Source token address
     * @param tokenOut Destination token address
     * @param amountIn Amount to swap
     * @return amountOut Expected output amount
     */
    function getRealQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external override returns (uint256 amountOut) {
        // Check quote cache first
        amountOut = _getCachedQuote(tokenIn, tokenOut, amountIn);
        if (amountOut > 0) {
            return amountOut;
        }

        // ✅ PRIORITY 1: OKX DEX (PRIMARY)
        if (okxIntegrationEnabled && okxDexAdapter != address(0)) {
            try OKXDexAdapter(payable(okxDexAdapter)).getQuote(tokenIn, tokenOut, amountIn)
            returns (uint256 okxAmount) {
                if (okxAmount > 0) {
                    _lastQuoteSource = LiquiditySource.OKX_DEX;
                    _cacheQuote(tokenIn, tokenOut, amountIn, okxAmount, LiquiditySource.OKX_DEX);
                    emit LiquiditySourceSelected(
                        tokenIn, tokenOut, amountIn,
                        LiquiditySource.OKX_DEX,
                        okxAmount,
                        block.timestamp
                    );
                    return okxAmount;
                }
            } catch {
                // OKX quote failed, continue to fallback
            }
        }

        // ⚠️ PRIORITY 2: Uniswap V4 (FALLBACK 1)
        bytes32 pairKey = _getPairKey(tokenIn, tokenOut);
        if (directPools[pairKey].isActive && universalRouter != address(0)) {
            try IQuoterV2(quoterV3).quoteExactInputSingle(
                IQuoterV2.QuoteExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    fee: directPools[pairKey].fee,
                    sqrtPriceLimitX96: 0
                })
            ) returns (uint256 v4Amount, uint160, uint32, uint256) {
                if (v4Amount > 0) {
                    _lastQuoteSource = LiquiditySource.UNISWAP_V4;
                    _cacheQuote(tokenIn, tokenOut, amountIn, v4Amount, LiquiditySource.UNISWAP_V4);
                    emit LiquiditySourceSelected(
                        tokenIn, tokenOut, amountIn,
                        LiquiditySource.UNISWAP_V4,
                        v4Amount,
                        block.timestamp
                    );
                    return v4Amount;
                }
            } catch {
                // V4 quote failed, continue to V3
            }
        }

        // ⚠️ PRIORITY 3: Uniswap V3 (FALLBACK 2)
        if (v3Pools[pairKey].isActive && quoterV3 != address(0)) {
            try IQuoterV2(quoterV3).quoteExactInputSingle(
                IQuoterV2.QuoteExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    fee: v3Pools[pairKey].feeTier,
                    sqrtPriceLimitX96: 0
                })
            ) returns (uint256 v3Amount, uint160, uint32, uint256) {
                if (v3Amount > 0) {
                    _lastQuoteSource = LiquiditySource.UNISWAP_V3;
                    _cacheQuote(tokenIn, tokenOut, amountIn, v3Amount, LiquiditySource.UNISWAP_V3);
                    emit LiquiditySourceSelected(
                        tokenIn, tokenOut, amountIn,
                        LiquiditySource.UNISWAP_V3,
                        v3Amount,
                        block.timestamp
                    );
                    return v3Amount;
                }
            } catch {
                // V3 quote failed, continue to V2
            }
        }

        // ⚠️ PRIORITY 4: Uniswap V2 (FALLBACK 3) - If implemented
        // For now, skip to simulation

        // ❌ PRIORITY 5: Simulation (LAST RESORT)
        (bool exists, , address[] memory path) = findRoute(tokenIn, tokenOut);
        if (!exists) {
            revert NoRouteFound();
        }
        
        _lastQuoteSource = LiquiditySource.SIMULATION;
        amountOut = _simulateSwap(path, amountIn);
        
        emit LiquiditySourceSelected(
            tokenIn, tokenOut, amountIn,
            LiquiditySource.SIMULATION,
            amountOut,
            block.timestamp
        );
        
        return amountOut;
    }

    /**
     * @notice Get quote with price impact validation
     * @dev Returns quote only if price impact is acceptable
     * @param tokenIn Source token address
     * @param tokenOut Destination token address
     * @param amountIn Amount to swap
     * @param tokenInDecimals Input token decimals
     * @param tokenOutDecimals Output token decimals
     * @param spotPrice Spot price from oracle (scaled to 18 decimals)
     * @return amountOut Expected output amount
     * @return impactBps Price impact in basis points
     */
    function getQuoteWithImpactValidation(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint8 tokenInDecimals,
        uint8 tokenOutDecimals,
        uint256 spotPrice
    ) external returns (uint256 amountOut, uint256 impactBps) {
        amountOut = this.getRealQuote(tokenIn, tokenOut, amountIn);
        
        PriceImpactLib.PriceImpactResult memory result = PriceImpactLib.calculatePriceImpact(
            amountIn,
            amountOut,
            tokenInDecimals,
            tokenOutDecimals,
            spotPrice
        );
        
        impactBps = result.impactBps;
        
        emit PriceImpactWarning(tokenIn, tokenOut, amountIn, impactBps, result.isAcceptable);
        
        if (!result.isAcceptable) {
            revert PriceImpactTooHigh(impactBps, okxMaxPriceImpactBps);
        }
    }

    /**
     * @notice Get last quote source used
     * @return source Last liquidity source
     */
    function getLastQuoteSource() external view returns (LiquiditySource) {
        return _lastQuoteSource;
    }

    /**
     * @notice Check if OKX DEX is available and enabled
     * @return available Whether OKX is available
     */
    function isOKXAvailable() external view returns (bool) {
        return okxIntegrationEnabled && 
               okxDexAdapter != address(0) && 
               okxDexAdapter.code.length > 0;
    }

    // ============ Internal Functions ============

    /**
     * @notice Get cached quote if still valid
     * @dev Checks if quote is within validity period
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     * @return amountOut Cached output amount (0 if expired or not found)
     */
    function _getCachedQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view returns (uint256 amountOut) {
        QuoteCache memory cache = quoteCache[tokenIn][amountIn][uint256(uint160(tokenOut))];
        
        if (!cache.valid) {
            return 0;
        }
        
        // Check if cache is still valid (within N blocks)
        if (block.number - cache.timestamp > quoteCacheValidityBlocks) {
            return 0; // Cache expired
        }
        
        return cache.amountOut;
    }

    /**
     * @notice Cache quote for future use
     * @dev Stores quote with timestamp for validity checking
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     * @param amountOut Output amount
     * @param source Liquidity source
     */
    function _cacheQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        LiquiditySource source
    ) internal {
        quoteCache[tokenIn][amountIn][uint256(uint160(tokenOut))] = QuoteCache({
            amountOut: amountOut,
            timestamp: block.number,
            source: source,
            valid: true
        });
        
        emit QuoteCached(tokenIn, tokenOut, amountIn, amountOut, source);
    }

    /**
     * @notice Execute swap with OKX DEX integration
     * @dev Routes to appropriate liquidity source based on quote
     * @param tokenIn Source token address
     * @param tokenOut Destination token address
     * @param amountIn Amount to swap
     * @param minAmountOut Minimum output (slippage protection)
     * @param recipient Address to receive output tokens
     * @return amountOut Actual output amount
     */
    function _executeSwapWithSource(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) internal returns (uint256 amountOut) {
        LiquiditySource source = _lastQuoteSource;
        
        if (source == LiquiditySource.OKX_DEX) {
            // Execute via OKX DEX
            require(okxIntegrationEnabled && okxDexAdapter != address(0), "OKX not available");
            amountOut = OKXDexAdapter(payable(okxDexAdapter)).swap{gas: 300000}(
                tokenIn,
                tokenOut,
                amountIn,
                minAmountOut
            );
        } else if (source == LiquiditySource.UNISWAP_V4) {
            // Execute via Uniswap V4 - TODO: Implement V4 swap
            revert("V4 swap not implemented yet");
        } else if (source == LiquiditySource.UNISWAP_V3) {
            // Execute via Uniswap V3
            bytes32 pairKey = _getPairKey(tokenIn, tokenOut);
            V3PoolConfig memory config = v3Pools[pairKey];
            require(config.isActive, "V3 pool not active");
            amountOut = _executeV3Swap(tokenIn, tokenOut, amountIn, minAmountOut, config.feeTier);
        } else if (source == LiquiditySource.UNISWAP_V2) {
            // Execute via Uniswap V2 (if implemented)
            revert NoRouteFound();
        } else {
            // Simulation - cannot execute
            revert NoRouteFound();
        }
        
        // Transfer to recipient
        IERC20(tokenOut).safeTransfer(recipient, amountOut);
    }
}
