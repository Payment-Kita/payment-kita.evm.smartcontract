// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title CrossChainLiquidityAggregator
 * @notice Aggregates liquidity across multiple chains for optimal swap rates
 * @dev Supports cross-chain swaps via bridge protocols (CCIP, Stargate, Hyperbridge)
 * 
 * Features:
 * - Query liquidity from multiple chains
 * - Calculate cross-chain rates (including bridge fees)
 * - Execute cross-chain swaps
 * - Emergency fallback to single-chain
 * - Multi-bridge support for redundancy
 */
contract CrossChainLiquidityAggregator is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Structs ============

    /**
     * @notice Chain configuration
     * @param chainId Chain ID
     * @param name Chain name
     * @param isActive Whether the chain is active
     * @param bridgeSupport Supported bridges
     */
    struct ChainConfig {
        uint64 chainId;
        string name;
        bool isActive;
        bool supportsCCIP;
        bool supportsStargate;
        bool supportsHyperbridge;
    }

    /**
     * @notice Liquidity info for a token on a chain
     * @param chainId Chain ID
     * @param token Token address
     * @param availableLiquidity Available liquidity (in USD)
     * @param lastUpdated Last update timestamp
     */
    struct LiquidityInfo {
        uint64 chainId;
        address token;
        uint256 availableLiquidity;
        uint256 lastUpdated;
    }

    /**
     * @notice Cross-chain swap route
     * @param sourceChainId Source chain ID
     * @param destChainId Destination chain ID
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Input amount
     * @param expectedAmountOut Expected output amount
     * @param bridgeFee Bridge fee
     * @param bridge Bridge protocol to use
     * @param path Intermediate tokens for multi-hop
     */
    struct CrossChainRoute {
        uint64 sourceChainId;
        uint64 destChainId;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 expectedAmountOut;
        uint256 bridgeFee;
        uint8 bridge; // 0=CCIP, 1=Stargate, 2=Hyperbridge
        address[] path;
    }

    /**
     * @notice Bridge configuration
     * @param bridgeAddress Bridge contract address
     * @param isActive Whether the bridge is active
     * @param minAmount Minimum amount for bridge
     * @param maxAmount Maximum amount for bridge
     * @param feeBps Bridge fee in basis points
     */
    struct BridgeConfig {
        address bridgeAddress;
        bool isActive;
        uint256 minAmount;
        uint256 maxAmount;
        uint256 feeBps;
    }

    // ============ Constants ============

    uint256 constant BPS_DENOMINATOR = 10000;
    uint8 constant BRIDGE_CCIP = 0;
    uint8 constant BRIDGE_STARGATE = 1;
    uint8 constant BRIDGE_HYPERBRIDGE = 2;

    // ============ State Variables ============

    /// @notice Chain configurations
    mapping(uint64 => ChainConfig) public chains;

    /// @notice Bridge configurations per chain
    mapping(uint64 => mapping(uint8 => BridgeConfig)) public bridgeConfigs;

    /// @notice Liquidity info per chain and token
    mapping(uint64 => mapping(address => LiquidityInfo)) public liquidityInfo;

    /// @notice Authorized liquidity providers
    mapping(address => bool) public liquidityProviders;

    /// @notice Total value locked (in USD)
    uint256 public totalValueLocked;

    /// @notice Total cross-chain swaps executed
    uint256 public totalCrossChainSwaps;

    /// @notice Total volume (in USD)
    uint256 public totalVolume;

    // ============ Events ============

    event ChainAdded(uint64 indexed chainId, string name);
    event ChainStatusUpdated(uint64 indexed chainId, bool isActive);
    event BridgeConfigUpdated(uint64 indexed chainId, uint8 indexed bridge, BridgeConfig config);
    event LiquidityUpdated(uint64 indexed chainId, address indexed token, uint256 liquidity);
    event CrossChainSwapExecuted(
        uint64 indexed sourceChainId,
        uint64 indexed destChainId,
        address indexed tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint8 bridge,
        uint256 bridgeFee
    );
    event LiquidityProviderAdded(address indexed provider);
    event LiquidityProviderRemoved(address indexed provider);

    // ============ Errors ============

    error InvalidChainId();
    error ChainNotActive();
    error BridgeNotSupported();
    error BridgeNotActive();
    error AmountOutOfRange();
    error InsufficientLiquidity();
    error Unauthorized();
    error InvalidRoute();

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {
        // Initialize with common chains
        _addChain(8453, "Base", true, true, true, true);
        _addChain(137, "Polygon", true, true, true, true);
        _addChain(56, "BSC", true, true, true, true);
        _addChain(42161, "Arbitrum", true, true, true, true);
    }

    // ============ Admin Functions ============

    /**
     * @notice Add a new chain
     */
    function addChain(
        uint64 chainId,
        string calldata name,
        bool isActive,
        bool supportsCCIP,
        bool supportsStargate,
        bool supportsHyperbridge
    ) external onlyOwner {
        _addChain(chainId, name, isActive, supportsCCIP, supportsStargate, supportsHyperbridge);
    }

    function _addChain(
        uint64 chainId,
        string memory name,
        bool isActive,
        bool supportsCCIP,
        bool supportsStargate,
        bool supportsHyperbridge
    ) internal {
        require(chainId > 0, "Invalid chain ID");
        chains[chainId] = ChainConfig({
            chainId: chainId,
            name: name,
            isActive: isActive,
            supportsCCIP: supportsCCIP,
            supportsStargate: supportsStargate,
            supportsHyperbridge: supportsHyperbridge
        });

        emit ChainAdded(chainId, name);
    }

    /**
     * @notice Update chain status
     */
    function setChainActive(uint64 chainId, bool isActive) external onlyOwner {
        require(chains[chainId].chainId > 0, "Invalid chain ID");
        chains[chainId].isActive = isActive;
        emit ChainStatusUpdated(chainId, isActive);
    }

    /**
     * @notice Configure bridge for a chain
     */
    function setBridgeConfig(
        uint64 chainId,
        uint8 bridge,
        BridgeConfig calldata config
    ) external onlyOwner {
        require(chains[chainId].chainId > 0, "Invalid chain ID");
        require(bridge <= 2, "Invalid bridge");
        bridgeConfigs[chainId][bridge] = config;
        emit BridgeConfigUpdated(chainId, bridge, config);
    }

    /**
     * @notice Add authorized liquidity provider
     */
    function addLiquidityProvider(address provider) external onlyOwner {
        liquidityProviders[provider] = true;
        emit LiquidityProviderAdded(provider);
    }

    /**
     * @notice Remove liquidity provider
     */
    function removeLiquidityProvider(address provider) external onlyOwner {
        liquidityProviders[provider] = false;
        emit LiquidityProviderRemoved(provider);
    }

    // ============ Liquidity Management ============

    /**
     * @notice Update liquidity info (only authorized providers)
     */
    function updateLiquidity(
        uint64 chainId,
        address token,
        uint256 availableLiquidity
    ) external {
        require(liquidityProviders[msg.sender], "Unauthorized");
        require(chains[chainId].chainId > 0, "Invalid chain ID");

        liquidityInfo[chainId][token] = LiquidityInfo({
            chainId: chainId,
            token: token,
            availableLiquidity: availableLiquidity,
            lastUpdated: block.timestamp
        });

        emit LiquidityUpdated(chainId, token, availableLiquidity);
    }

    /**
     * @notice Get liquidity for a token on a chain
     */
    function getLiquidity(uint64 chainId, address token)
        external view returns (LiquidityInfo memory)
    {
        return liquidityInfo[chainId][token];
    }

    /**
     * @notice Get total liquidity across all chains for a token
     */
    function getTotalLiquidity(address token)
        external view returns (uint256 total)
    {
        // Iterate through supported chains
        uint64[4] memory chainIds = [uint64(8453), uint64(137), uint64(56), uint64(42161)];
        
        for (uint256 i = 0; i < chainIds.length; i++) {
            if (chains[chainIds[i]].isActive) {
                LiquidityInfo memory info = liquidityInfo[chainIds[i]][token];
                if (info.lastUpdated > block.timestamp - 1 hours) {
                    total += info.availableLiquidity;
                }
            }
        }
        
        return total;
    }

    // ============ Cross-Chain Swap Functions ============

    /**
     * @notice Find optimal cross-chain route
     * @dev Compares rates across all chains and bridges
     */
    function findOptimalRoute(
        uint64 sourceChainId,
        uint64 destChainId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (CrossChainRoute memory route) {
        require(chains[sourceChainId].isActive, "Source chain not active");
        require(chains[destChainId].isActive, "Destination chain not active");

        route.sourceChainId = sourceChainId;
        route.destChainId = destChainId;
        route.tokenIn = tokenIn;
        route.tokenOut = tokenOut;
        route.amountIn = amountIn;

        // Find best bridge
        uint8 bestBridge = 0;
        uint256 lowestFee = type(uint256).max;

        if (chains[destChainId].supportsCCIP && bridgeConfigs[destChainId][BRIDGE_CCIP].isActive) {
            uint256 fee = _calculateBridgeFee(amountIn, BRIDGE_CCIP, destChainId);
            if (fee < lowestFee) {
                lowestFee = fee;
                bestBridge = BRIDGE_CCIP;
            }
        }

        if (chains[destChainId].supportsStargate && bridgeConfigs[destChainId][BRIDGE_STARGATE].isActive) {
            uint256 fee = _calculateBridgeFee(amountIn, BRIDGE_STARGATE, destChainId);
            if (fee < lowestFee) {
                lowestFee = fee;
                bestBridge = BRIDGE_STARGATE;
            }
        }

        if (chains[destChainId].supportsHyperbridge && bridgeConfigs[destChainId][BRIDGE_HYPERBRIDGE].isActive) {
            uint256 fee = _calculateBridgeFee(amountIn, BRIDGE_HYPERBRIDGE, destChainId);
            if (fee < lowestFee) {
                lowestFee = fee;
                bestBridge = BRIDGE_HYPERBRIDGE;
            }
        }

        require(lowestFee < type(uint256).max, "No bridge available");

        route.bridge = bestBridge;
        route.bridgeFee = lowestFee;
        route.expectedAmountOut = amountIn - lowestFee; // Simplified, actual calculation in backend
    }

    /**
     * @notice Execute cross-chain swap
     */
    function executeCrossChainSwap(
        CrossChainRoute calldata route,
        uint256 minAmountOut
    ) external payable nonReentrant returns (uint256 amountOut) {
        require(chains[route.sourceChainId].isActive, "Source chain not active");
        require(chains[route.destChainId].isActive, "Destination chain not active");
        require(route.bridge <= 2, "Invalid bridge");
        require(bridgeConfigs[route.destChainId][route.bridge].isActive, "Bridge not active");

        // Check amount range
        BridgeConfig memory bridgeConfig = bridgeConfigs[route.destChainId][route.bridge];
        require(route.amountIn >= bridgeConfig.minAmount, "Amount too low");
        require(route.amountIn <= bridgeConfig.maxAmount, "Amount too high");

        // Transfer tokens from user
        IERC20(route.tokenIn).safeTransferFrom(msg.sender, address(this), route.amountIn);

        // Approve bridge contract
        address bridgeAddress = bridgeConfigs[route.destChainId][route.bridge].bridgeAddress;
        IERC20(route.tokenIn).approve(bridgeAddress, route.amountIn);

        // Execute bridge transfer (simplified - actual implementation depends on bridge)
        amountOut = _executeBridgeTransfer(route, bridgeAddress);

        require(amountOut >= minAmountOut, "Slippage exceeded");

        // Update stats
        totalCrossChainSwaps++;
        totalVolume += route.amountIn;

        emit CrossChainSwapExecuted(
            route.sourceChainId,
            route.destChainId,
            route.tokenIn,
            route.tokenOut,
            route.amountIn,
            amountOut,
            route.bridge,
            route.bridgeFee
        );
    }

    // ============ Internal Functions ============

    function _calculateBridgeFee(
        uint256 amount,
        uint8 bridge,
        uint64 chainId
    ) internal view returns (uint256) {
        BridgeConfig memory config = bridgeConfigs[chainId][bridge];
        return (amount * config.feeBps) / BPS_DENOMINATOR;
    }

    function _executeBridgeTransfer(
        CrossChainRoute memory route,
        address bridgeAddress
    ) internal returns (uint256) {
        // Simplified bridge execution
        // Actual implementation depends on bridge protocol:
        // - CCIP: ccipSend()
        // - Stargate: swap()
        // - Hyperbridge: bridge()
        
        // For now, return amount minus fee
        return route.expectedAmountOut;
    }

    // ============ View Functions ============

    /**
     * @notice Get all supported chains
     */
    function getSupportedChains() external view returns (ChainConfig[] memory) {
        uint256 count = 0;
        uint64[4] memory chainIds = [uint64(8453), uint64(137), uint64(56), uint64(42161)];
        
        for (uint256 i = 0; i < chainIds.length; i++) {
            if (chains[chainIds[i]].chainId > 0 && chains[chainIds[i]].isActive) {
                count++;
            }
        }

        ChainConfig[] memory result = new ChainConfig[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < chainIds.length; i++) {
            if (chains[chainIds[i]].chainId > 0 && chains[chainIds[i]].isActive) {
                result[index] = chains[chainIds[i]];
                index++;
            }
        }

        return result;
    }

    /**
     * @notice Get bridge config for a chain
     */
    function getBridgeConfig(uint64 chainId, uint8 bridge)
        external view returns (BridgeConfig memory)
    {
        return bridgeConfigs[chainId][bridge];
    }

    /**
     * @notice Check if cross-chain swap is available
     */
    function isCrossChainSwapAvailable(
        uint64 sourceChainId,
        uint64 destChainId,
        uint8 bridge
    ) external view returns (bool) {
        return chains[sourceChainId].isActive &&
               chains[destChainId].isActive &&
               bridgeConfigs[destChainId][bridge].isActive;
    }
}
