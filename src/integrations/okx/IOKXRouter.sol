// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IOKXRouter
 * @notice Interface for OKX DEX Router integration
 * @dev Based on OKX DEX Router contract at 0x4409921Ae43a39a11D90F7B7F96cfd0B8093d9fC (Base)
 * 
 * OKX DEX is a liquidity aggregator that supports:
 * - Multiple DEX protocols (Uniswap V2/V3, Curve, Balancer, etc.)
 * - Split routing for better prices
 * - DAG (Directed Acyclic Graph) routing for complex swaps
 * - Multi-hop swaps with intermediate tokens
 */
interface IOKXRouter {
    /**
     * @notice Base request structure for swap operations
     * @param fromToken Source token address (use ETH_PLACEHOLDER for native)
     * @param toToken Destination token address
     * @param fromTokenAmount Amount of source tokens to swap
     * @param minReturnAmount Minimum amount of destination tokens (slippage protection)
     * @param deadLine Swap deadline (Unix timestamp)
     */
    struct BaseRequest {
        uint256 fromToken;
        address toToken;
        uint256 fromTokenAmount;
        uint256 minReturnAmount;
        uint256 deadLine;
    }

    /**
     * @notice Router path structure for multi-protocol routing
     * @param mixAdapters Array of adapter contracts for different protocols
     * @param assetTo Array of intermediate token addresses
     * @param rawData Encoded pool information (address, weight, direction)
     * @param extraData Protocol-specific data for each adapter
     * @param fromToken Source token for this path segment
     */
    struct RouterPath {
        address[] mixAdapters;
        address[] assetTo;
        uint256[] rawData;
        bytes[] extraData;
        uint256 fromToken;
    }

    /**
     * @notice Commission/referral information
     * @param isFromTokenCommission Whether commission is taken from input token
     * @param isToTokenCommission Whether commission is taken from output token
     * @param token Token address for commission
     * @param toBCommission Commission basis points
     * @param commissionLength Number of referrers
     * @param commissionRate Array of commission rates for each referrer
     * @param referrerAddress Array of referrer addresses (max 8)
     */
    struct CommissionInfo {
        bool isFromTokenCommission;
        bool isToTokenCommission;
        address token;
        uint256 toBCommission;
        uint256 commissionLength;
        address[] referrerAddress;
        uint256[] referrerCommissionRate;
    }

    /**
     * @notice Execute a smart swap with order ID tracking
     * @dev Main swap function that supports multi-path, multi-protocol swaps
     * @param request Base swap request parameters
     * @param paths Array of router paths for split routing
     * @param commission Commission/referral information
     * @return returnAmount Actual amount of destination tokens received
     */
    function smartSwapByOrderId(
        BaseRequest calldata request,
        RouterPath[] calldata paths,
        CommissionInfo calldata commission
    ) external payable returns (uint256 returnAmount);

    /**
     * @notice Execute a smart swap to specific receiver
     * @param request Base swap request parameters
     * @param paths Array of router paths
     * @param commission Commission information
     * @param receiver Address to receive output tokens
     * @return returnAmount Actual amount received
     */
    function smartSwapTo(
        BaseRequest calldata request,
        RouterPath[] calldata paths,
        CommissionInfo calldata commission,
        address receiver
    ) external payable returns (uint256 returnAmount);

    /**
     * @notice Execute Uniswap V3 specific swap
     * @param receiver Address to receive output tokens
     * @param fromToken Source token address
     * @param toToken Destination token address
     * @param fromTokenAmount Amount to swap
     * @param minReturnAmount Minimum return (slippage protection)
     * @param path Encoded Uniswap V3 path (pool fees, token addresses)
     * @return returnAmount Actual amount received
     */
    function uniswapV3SwapTo(
        address receiver,
        address fromToken,
        address toToken,
        uint256 fromTokenAmount,
        uint256 minReturnAmount,
        bytes calldata path
    ) external payable returns (uint256 returnAmount);

    /**
     * @notice Execute Uniswap V3 swap with BaseRequest structure
     * @param request Base request parameters
     * @param path Encoded Uniswap V3 path
     * @param commission Commission information
     * @return returnAmount Actual amount received
     */
    function uniswapV3SwapToWithBaseRequest(
        BaseRequest calldata request,
        bytes calldata path,
        CommissionInfo calldata commission
    ) external payable returns (uint256 returnAmount);

    /**
     * @notice Get quote for swap without executing
     * @dev View function to estimate output amount
     * @param fromToken Source token address
     * @param toToken Destination token address
     * @param fromTokenAmount Amount to swap
     * @return toTokenAmount Expected output amount
     */
    function getQuote(
        uint256 fromToken,
        address toToken,
        uint256 fromTokenAmount
    ) external view returns (uint256 toTokenAmount);

    /**
     * @notice Get quote with router paths
     * @dev Returns both quote and optimal paths
     * @param fromToken Source token address
     * @param toToken Destination token address
     * @param fromTokenAmount Amount to swap
     * @return toTokenAmount Expected output amount
     * @return paths Optimal router paths for execution
     */
    function getQuoteAndPaths(
        uint256 fromToken,
        address toToken,
        uint256 fromTokenAmount
    ) external view returns (
        uint256 toTokenAmount,
        RouterPath[] memory paths
    );

    /**
     * @notice Execute DAG (Directed Acyclic Graph) swap
     * @dev Complex multi-path swap with graph-based routing
     * @param request Base request parameters
     * @param paths DAG router paths
     * @param commission Commission information
     * @return returnAmount Actual amount received
     */
    function dagSwapByOrderId(
        BaseRequest calldata request,
        RouterPath[] calldata paths,
        CommissionInfo calldata commission
    ) external payable returns (uint256 returnAmount);

    /**
     * @notice Execute DAG swap to specific receiver
     * @param request Base request parameters
     * @param paths DAG router paths
     * @param commission Commission information
     * @param receiver Address to receive tokens
     * @return returnAmount Actual amount received
     */
    function dagSwapTo(
        BaseRequest calldata request,
        RouterPath[] calldata paths,
        CommissionInfo calldata commission,
        address receiver
    ) external payable returns (uint256 returnAmount);

    /**
     * @notice Wrap/unwrap native token (ETH <-> WETH)
     * @param request Base request (fromToken/toToken for wrap/unwrap)
     * @param to Address to receive wrapped/unwrapped tokens
     * @return returnAmount Amount of wrapped/unwrapped tokens
     */
    function swapWrap(
        BaseRequest calldata request,
        address to
    ) external payable returns (uint256 returnAmount);

    /**
     * @notice Get supported protocols/adapters
     * @return adapters Array of supported adapter addresses
     */
    function getSupportedAdapters() external view returns (address[] memory adapters);

    /**
     * @notice Check if a token pair is supported
     * @param fromToken Source token address
     * @param toToken Destination token address
     * @return supported Whether the pair is supported
     */
    function isPairSupported(
        uint256 fromToken,
        address toToken
    ) external view returns (bool supported);
}
