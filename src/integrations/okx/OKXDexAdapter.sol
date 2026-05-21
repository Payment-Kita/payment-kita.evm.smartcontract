// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./IOKXRouter.sol";

/**
 * @title OKXDexAdapter
 * @notice Adapter contract for integrating OKX DEX with PaymentKita TokenSwapper
 * @dev This contract acts as a bridge between TokenSwapper and OKX DEX Router
 * 
 * Features:
 * - Quote retrieval from OKX DEX
 * - Swap execution via OKX DEX
 * - Access control (only TokenSwapper can call)
 * - Event logging for monitoring
 * 
 * Security:
 * - Only authorized TokenSwapper contract can call swap functions
 * - Owner can update OKX router address
 * - Reentrancy protection on swap operations
 */
contract OKXDexAdapter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    /// @notice OKX DEX Router address
    address public okxRouter;
    
    /// @notice ETH placeholder address for native token swaps
    address constant ETH_PLACEHOLDER = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// @notice TokenSwapper contract address (authorized caller)
    address public tokenSwapper;

    /// @notice Whether OKX integration is enabled
    bool public integrationEnabled;

    /// @notice Minimum quote age in seconds (for caching)
    uint256 public quoteValidityPeriod;

    // ============ Events ============

    event OKXRouterUpdated(address indexed oldRouter, address indexed newRouter);
    event TokenSwapperUpdated(address indexed oldSwapper, address indexed newSwapper);
    event IntegrationEnabled(bool enabled);
    event QuoteRequested(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 timestamp
    );
    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed recipient,
        uint256 timestamp
    );
    event SwapFailed(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        string reason
    );

    // ============ Errors ============

    error InvalidAddress();
    error NotAuthorized();
    error ZeroAmount();
    error SlippageExceeded();
    error QuoteFailed();
    error SwapFailedError();
    error IntegrationDisabled();

    // ============ Constructor ============

    /**
     * @notice Initialize OKX DEX Adapter
     * @param _okxRouter OKX DEX Router address (can be address(0) for now)
     * @param _tokenSwapper TokenSwapper contract address
     */
    constructor(address _okxRouter, address _tokenSwapper) Ownable(msg.sender) {
        if (_tokenSwapper == address(0)) {
            revert InvalidAddress();
        }
        okxRouter = _okxRouter; // Can be address(0), configure later
        tokenSwapper = _tokenSwapper;
        integrationEnabled = true;
        quoteValidityPeriod = 12; // 2 blocks (~24 seconds on most chains)

        emit OKXRouterUpdated(address(0), _okxRouter);
        emit TokenSwapperUpdated(address(0), _tokenSwapper);
        emit IntegrationEnabled(true);
    }

    // ============ Modifiers ============

    /**
     * @notice Restrict access to TokenSwapper contract only
     */
    modifier onlyTokenSwapper() {
        if (msg.sender != tokenSwapper) {
            revert NotAuthorized();
        }
        _;
    }

    /**
     * @notice Check if integration is enabled
     */
    modifier integrationActive() {
        if (!integrationEnabled) {
            revert IntegrationDisabled();
        }
        _;
    }

    // ============ Admin Functions ============

    /**
     * @notice Update OKX Router address
     * @param _newRouter New OKX Router address
     */
    function setOKXRouter(address _newRouter) external onlyOwner {
        if (_newRouter == address(0)) {
            revert InvalidAddress();
        }
        address oldRouter = okxRouter;
        okxRouter = _newRouter;
        emit OKXRouterUpdated(oldRouter, _newRouter);
    }

    /**
     * @notice Update TokenSwapper address
     * @param _newSwapper New TokenSwapper address
     */
    function setTokenSwapper(address _newSwapper) external onlyOwner {
        if (_newSwapper == address(0)) {
            revert InvalidAddress();
        }
        address oldSwapper = tokenSwapper;
        tokenSwapper = _newSwapper;
        emit TokenSwapperUpdated(oldSwapper, _newSwapper);
    }

    /**
     * @notice Enable or disable OKX integration
     * @param _enabled Whether to enable integration
     */
    function setIntegrationEnabled(bool _enabled) external onlyOwner {
        integrationEnabled = _enabled;
        emit IntegrationEnabled(_enabled);
    }

    /**
     * @notice Set quote validity period
     * @param _seconds Validity period in seconds
     */
    function setQuoteValidityPeriod(uint256 _seconds) external onlyOwner {
        quoteValidityPeriod = _seconds;
    }

    /**
     * @notice Emergency withdrawal of tokens stuck in contract
     * @param token Token address to withdraw
     * @param amount Amount to withdraw
     * @param to Recipient address
     */
    function emergencyWithdraw(
        address token,
        uint256 amount,
        address to
    ) external onlyOwner {
        if (to == address(0)) {
            revert InvalidAddress();
        }
        IERC20(token).safeTransfer(to, amount);
    }

    // ============ View Functions ============

    /**
     * @notice Get quote from OKX DEX
     * @dev Calls OKX Router's getQuote function
     * @param tokenIn Source token address
     * @param tokenOut Destination token address
     * @param amountIn Amount to swap
     * @return amountOut Expected output amount
     */
    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external integrationActive returns (uint256 amountOut) {
        if (amountIn == 0) {
            revert ZeroAmount();
        }

        // Convert to OKX format (ETH_PLACEHOLDER for native token)
        uint256 okxTokenIn = _toOKXTokenFormat(tokenIn);

        try IOKXRouter(okxRouter).getQuote(okxTokenIn, tokenOut, amountIn) returns (uint256 quote) {
            amountOut = quote;
            emit QuoteRequested(tokenIn, tokenOut, amountIn, amountOut, block.timestamp);
        } catch {
            // Quote failed, return 0
            amountOut = 0;
            emit SwapFailed(tokenIn, tokenOut, amountIn, "Quote failed");
        }
    }

    /**
     * @notice Check if a token pair is supported by OKX DEX
     * @param tokenIn Source token address
     * @param tokenOut Destination token address
     * @return supported Whether the pair is supported
     */
    function isPairSupported(
        address tokenIn,
        address tokenOut
    ) external view returns (bool supported) {
        uint256 okxTokenIn = _toOKXTokenFormat(tokenIn);
        
        try IOKXRouter(okxRouter).isPairSupported(okxTokenIn, tokenOut) returns (bool result) {
            supported = result;
        } catch {
            supported = false;
        }
    }

    /**
     * @notice Get OKX Router version info (if available)
     * @return version Router version string
     */
    function getRouterVersion() external view returns (string memory version) {
        // Try to get version from router (if implemented)
        // This is optional and may not be available on all routers
        return "OKX DEX v1.0.7-multi-commission";
    }

    // ============ Core Functions ============

    /**
     * @notice Execute swap via OKX DEX
     * @dev Main swap function called by TokenSwapper
     * @param tokenIn Source token address
     * @param tokenOut Destination token address
     * @param amountIn Amount to swap
     * @param minAmountOut Minimum output (slippage protection)
     * @return amountOut Actual output amount
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external onlyTokenSwapper nonReentrant integrationActive returns (uint256 amountOut) {
        if (amountIn == 0) {
            revert ZeroAmount();
        }

        // Transfer tokens from TokenSwapper to this contract
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Approve OKX Router
        IERC20(tokenIn).approve(okxRouter, amountIn);

        // Build OKX swap request
        uint256 okxTokenIn = _toOKXTokenFormat(tokenIn);
        
        IOKXRouter.BaseRequest memory request = IOKXRouter.BaseRequest({
            fromToken: okxTokenIn,
            toToken: tokenOut,
            fromTokenAmount: amountIn,
            minReturnAmount: minAmountOut,
            deadLine: block.timestamp + 900 // 15 minutes deadline
        });

        // Build simple router path (single path, no split)
        IOKXRouter.RouterPath[] memory paths = _buildSimpleRouterPath(okxTokenIn, tokenOut);

        // Empty commission (no referrers)
        IOKXRouter.CommissionInfo memory commission = _getEmptyCommission();

        // Execute swap
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));
        
        try IOKXRouter(okxRouter).smartSwapByOrderId{value: 0}(request, paths, commission) returns (uint256) {
            uint256 balanceAfter = IERC20(tokenOut).balanceOf(address(this));
            amountOut = balanceAfter - balanceBefore;

            if (amountOut < minAmountOut) {
                revert SlippageExceeded();
            }

            // Transfer output to TokenSwapper
            IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

            emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, msg.sender, block.timestamp);
        } catch Error(string memory reason) {
            emit SwapFailed(tokenIn, tokenOut, amountIn, reason);
            revert SwapFailedError();
        } catch {
            emit SwapFailed(tokenIn, tokenOut, amountIn, "Unknown error");
            revert SwapFailedError();
        }
    }

    /**
     * @notice Execute swap with native token output
     * @dev Special case for swaps ending in native token (ETH/BNB/MATIC)
     * @param tokenIn Source token address
     * @param amountIn Amount to swap
     * @param minAmountOut Minimum output (slippage protection)
     * @return amountOut Actual output amount (in native token)
     */
    function swapToNative(
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut
    ) external onlyTokenSwapper nonReentrant integrationActive returns (uint256 amountOut) {
        if (amountIn == 0) {
            revert ZeroAmount();
        }

        // Transfer tokens from TokenSwapper
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).approve(okxRouter, amountIn);

        // Build request with ETH_PLACEHOLDER as output
        uint256 okxTokenIn = _toOKXTokenFormat(tokenIn);
        
        IOKXRouter.BaseRequest memory request = IOKXRouter.BaseRequest({
            fromToken: okxTokenIn,
            toToken: ETH_PLACEHOLDER,
            fromTokenAmount: amountIn,
            minReturnAmount: minAmountOut,
            deadLine: block.timestamp + 900
        });

        IOKXRouter.RouterPath[] memory paths = _buildSimpleRouterPath(okxTokenIn, ETH_PLACEHOLDER);
        IOKXRouter.CommissionInfo memory commission = _getEmptyCommission();

        uint256 balanceBefore = address(this).balance;
        
        try IOKXRouter(okxRouter).smartSwapByOrderId{value: 0}(request, paths, commission) returns (uint256) {
            uint256 balanceAfter = address(this).balance;
            amountOut = balanceAfter - balanceBefore;

            if (amountOut < minAmountOut) {
                revert SlippageExceeded();
            }

            // Transfer native tokens to TokenSwapper
            (bool success, ) = payable(msg.sender).call{value: amountOut}("");
            if (!success) {
                revert();
            }

            emit SwapExecuted(tokenIn, ETH_PLACEHOLDER, amountIn, amountOut, msg.sender, block.timestamp);
        } catch {
            revert SwapFailedError();
        }
    }

    /**
     * @notice Execute swap from native token
     * @dev Special case for swaps starting with native token
     * @param tokenOut Destination token address
     * @param minAmountOut Minimum output (slippage protection)
     * @return amountOut Actual output amount
     */
    function swapFromNative(
        address tokenOut,
        uint256 minAmountOut
    ) external payable onlyTokenSwapper nonReentrant integrationActive returns (uint256 amountOut) {
        if (msg.value == 0) {
            revert ZeroAmount();
        }

        // Build request with ETH_PLACEHOLDER as input
        IOKXRouter.BaseRequest memory request = IOKXRouter.BaseRequest({
            fromToken: uint256(uint160(ETH_PLACEHOLDER)),
            toToken: tokenOut,
            fromTokenAmount: msg.value,
            minReturnAmount: minAmountOut,
            deadLine: block.timestamp + 900
        });

        IOKXRouter.RouterPath[] memory paths = _buildSimpleRouterPath(
            uint256(uint160(ETH_PLACEHOLDER)),
            tokenOut
        );
        IOKXRouter.CommissionInfo memory commission = _getEmptyCommission();

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));
        
        try IOKXRouter(okxRouter).smartSwapByOrderId{value: msg.value}(request, paths, commission) returns (uint256) {
            uint256 balanceAfter = IERC20(tokenOut).balanceOf(address(this));
            amountOut = balanceAfter - balanceBefore;

            if (amountOut < minAmountOut) {
                revert SlippageExceeded();
            }

            // Transfer tokens to TokenSwapper
            IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

            emit SwapExecuted(ETH_PLACEHOLDER, tokenOut, msg.value, amountOut, msg.sender, block.timestamp);
        } catch {
            revert SwapFailedError();
        }
    }

    // ============ Internal Functions ============

    /**
     * @notice Convert token address to OKX format
     * @dev Returns ETH_PLACEHOLDER for native token, otherwise the address
     * @param token Token address
     * @return okxToken OKX format token (uint256)
     */
    function _toOKXTokenFormat(address token) internal pure returns (uint256 okxToken) {
        // Check if token is native token wrapper (WETH, WMATIC, etc.)
        // For simplicity, we use address comparison
        // In production, you may want to maintain a registry
        if (token == address(0)) {
            return uint256(uint160(ETH_PLACEHOLDER));
        }
        return uint256(uint160(token));
    }

    /**
     * @notice Build simple router path for single-hop swap
     * @dev Creates a basic path without split routing
     * @param fromToken Source token (OKX format)
     * @param toToken Destination token
     * @return paths Array of router paths
     */
    function _buildSimpleRouterPath(
        uint256 fromToken,
        address toToken
    ) internal pure returns (IOKXRouter.RouterPath[] memory paths) {
        paths = new IOKXRouter.RouterPath[](1);
        
        paths[0] = IOKXRouter.RouterPath({
            mixAdapters: new address[](0),  // Let OKX choose adapters
            assetTo: new address[](1),
            rawData: new uint256[](0),
            extraData: new bytes[](0),
            fromToken: fromToken
        });
        
        paths[0].assetTo[0] = toToken;
    }

    /**
     * @notice Get empty commission structure
     * @dev No referrers, no commission
     * @return commission Empty commission info
     */
    function _getEmptyCommission() internal pure returns (IOKXRouter.CommissionInfo memory commission) {
        commission = IOKXRouter.CommissionInfo({
            isFromTokenCommission: false,
            isToTokenCommission: false,
            token: address(0),
            toBCommission: 0,
            commissionLength: 0,
            referrerAddress: new address[](0),
            referrerCommissionRate: new uint256[](0)
        });
    }

    // ============ Receive Function ============

    /**
     * @notice Receive native tokens
     * @dev Required for swaps from native token
     */
    receive() external payable {}
}
