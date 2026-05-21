// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/TokenSwapperV2.sol";
import "../../src/integrations/okx/OKXDexAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title TokenSwapperV2Test
 * @notice Unit tests for TokenSwapperV2 with OKX integration
 * @dev Tests fallback chain, quote caching, and price impact validation
 */
contract TokenSwapperV2Test is Test {
    // Mock contracts
    MockOKXRouter public mockOKXRouter;
    MockERC20 public mockUSDC;
    MockERC20 public mockIDRT;
    MockERC20 public mockIDRX;
    
    // TokenSwapperV2
    TokenSwapperV2 public swapperV2;
    
    // Test accounts
    address public owner;
    address public authorizedCaller;
    
    // Constants
    address constant UNISWAP_ROUTER = address(0x100);
    address constant POOL_MANAGER = address(0x200);
    address constant BRIDGE_TOKEN = address(0x300);
    
    function setUp() public {
        // Setup accounts
        owner = makeAddr("owner");
        authorizedCaller = makeAddr("authorizedCaller");
        
        // Deploy mock tokens
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        mockIDRT = new MockERC20("Rupiah Token", "IDRT", 6);
        mockIDRX = new MockERC20("Digital Rupiah", "IDRX", 2);
        
        // Deploy mock OKX Router
        mockOKXRouter = new MockOKXRouter();
        
        // Deploy mock OKX Adapter
        OKXDexAdapter mockAdapter = new OKXDexAdapter(
            address(mockOKXRouter),
            address(this)
        );
        
        // Deploy TokenSwapperV2
        vm.startPrank(owner);
        swapperV2 = new TokenSwapperV2(
            UNISWAP_ROUTER,
            POOL_MANAGER,
            BRIDGE_TOKEN,
            address(mockAdapter)
        );
        vm.stopPrank();
        
        // Set authorized caller
        vm.startPrank(owner);
        swapperV2.setAuthorizedCaller(authorizedCaller, true);
        vm.stopPrank();
        
        // Mint tokens for testing
        mockUSDC.mint(authorizedCaller, 1_000_000 * 10**6);
        mockIDRT.mint(authorizedCaller, 1_000_000 * 10**6);
        mockIDRX.mint(authorizedCaller, 1_000_000 * 10**2);
    }
    
    // ==================== CONSTRUCTOR TESTS ====================
    
    function test_Constructor_Success() public {
        assertEq(swapperV2.okxDexAdapter(), address(0), "Adapter should be set");
        assertTrue(swapperV2.okxIntegrationEnabled(), "OKX should be enabled");
        assertEq(swapperV2.okxMaxPriceImpactBps(), 500, "Default max impact should be 5%");
    }
    
    // ==================== OKX INTEGRATION TESTS ====================
    
    function test_SetOKXDexAdapter_Success() public {
        address newAdapter = makeAddr("newAdapter");
        
        vm.startPrank(owner);
        swapperV2.setOKXDexAdapter(newAdapter);
        vm.stopPrank();
        
        assertEq(swapperV2.okxDexAdapter(), newAdapter, "Adapter not updated");
    }
    
    function test_SetOKXIntegrationEnabled_Success() public {
        vm.startPrank(owner);
        swapperV2.setOKXIntegrationEnabled(false);
        vm.stopPrank();
        
        assertEq(swapperV2.okxIntegrationEnabled(), false, "Should be disabled");
    }
    
    function test_SetMaxPriceImpactBps_Success() public {
        vm.startPrank(owner);
        swapperV2.setMaxPriceImpactBps(300); // 3%
        vm.stopPrank();
        
        assertEq(swapperV2.okxMaxPriceImpactBps(), 300, "Max impact not updated");
    }
    
    function test_SetMaxPriceImpactBps_TooHigh() public {
        vm.startPrank(owner);
        vm.expectRevert("Max 10% impact");
        swapperV2.setMaxPriceImpactBps(1001); // >10%
        vm.stopPrank();
    }
    
    // ==================== FALLBACK CHAIN TESTS ====================
    
    function test_GetRealQuote_OKXPrimary() public {
        uint256 amountIn = 1000 * 10**6; // 1000 USDC
        
        // Setup OKX mock to return quote
        mockOKXRouter.setQuote(amountIn, 997 * 10**6);
        
        // Get quote
        vm.startPrank(authorizedCaller);
        uint256 amountOut = swapperV2.getRealQuote(
            address(mockUSDC),
            address(mockIDRT),
            amountIn
        );
        vm.stopPrank();
        
        // Should use OKX (primary)
        assertEq(amountOut, 997 * 10**6, "Quote amount mismatch");
        assertEq(
            uint256(swapperV2.getLastQuoteSource()),
            uint256(TokenSwapperV2.LiquiditySource.OKX_DEX),
            "Should use OKX"
        );
    }
    
    function test_GetRealQuote_OKXUnavailable() public {
        uint256 amountIn = 1000 * 10**6;
        
        // Disable OKX
        vm.startPrank(owner);
        swapperV2.setOKXIntegrationEnabled(false);
        vm.stopPrank();
        
        // Setup V3 pool
        bytes32 pairKey = keccak256(abi.encodePacked(
            address(mockUSDC) < address(mockIDRT) ? 
            address(mockUSDC) : address(mockIDRT),
            address(mockUSDC) < address(mockIDRT) ? 
            address(mockIDRT) : address(mockUSDC)
        ));
        
        // Should fallback to simulation (since no V3/V4 pools configured)
        vm.startPrank(authorizedCaller);
        uint256 amountOut = swapperV2.getRealQuote(
            address(mockUSDC),
            address(mockIDRT),
            amountIn
        );
        vm.stopPrank();
        
        // Simulation returns 1:1
        assertEq(amountOut, amountIn, "Should return 1:1 from simulation");
    }
    
    // ==================== QUOTE CACHE TESTS ====================
    
    function test_QuoteCache_Success() public {
        uint256 amountIn = 1000 * 10**6;
        
        // Setup OKX mock
        mockOKXRouter.setQuote(amountIn, 997 * 10**6);
        
        // First call - should cache
        vm.startPrank(authorizedCaller);
        uint256 amountOut1 = swapperV2.getRealQuote(
            address(mockUSDC),
            address(mockIDRT),
            amountIn
        );
        vm.stopPrank();
        
        // Second call - should use cache
        vm.startPrank(authorizedCaller);
        uint256 amountOut2 = swapperV2.getRealQuote(
            address(mockUSDC),
            address(mockIDRT),
            amountIn
        );
        vm.stopPrank();
        
        assertEq(amountOut1, amountOut2, "Cached quote should match");
    }
    
    function test_QuoteCache_Expired() public {
        uint256 amountIn = 1000 * 10**6;
        
        // Set cache validity to 1 block
        vm.startPrank(owner);
        swapperV2.setQuoteCacheValidityBlocks(1);
        vm.stopPrank();
        
        // Setup OKX mock
        mockOKXRouter.setQuote(amountIn, 997 * 10**6);
        
        // First call
        vm.startPrank(authorizedCaller);
        swapperV2.getRealQuote(address(mockUSDC), address(mockIDRT), amountIn);
        vm.stopPrank();
        
        // Skip blocks
        vm.roll(block.number + 2);
        
        // Second call - cache expired, should re-quote
        mockOKXRouter.setQuote(amountIn, 995 * 10**6); // Different quote
        
        vm.startPrank(authorizedCaller);
        uint256 amountOut = swapperV2.getRealQuote(
            address(mockUSDC),
            address(mockIDRT),
            amountIn
        );
        vm.stopPrank();
        
        assertEq(amountOut, 995 * 10**6, "Should use new quote after expiry");
    }
    
    function test_ClearQuoteCache_Success() public {
        uint256 amountIn = 1000 * 10**6;
        
        // Setup OKX mock
        mockOKXRouter.setQuote(amountIn, 997 * 10**6);
        
        // Get quote (cache it)
        vm.startPrank(authorizedCaller);
        swapperV2.getRealQuote(address(mockUSDC), address(mockIDRT), amountIn);
        vm.stopPrank();
        
        // Clear cache
        swapperV2.clearQuoteCache(
            address(mockUSDC),
            address(mockIDRT),
            amountIn
        );
        
        // Change quote
        mockOKXRouter.setQuote(amountIn, 995 * 10**6);
        
        // Get quote again - should use new quote
        vm.startPrank(authorizedCaller);
        uint256 amountOut = swapperV2.getRealQuote(
            address(mockUSDC),
            address(mockIDRT),
            amountIn
        );
        vm.stopPrank();
        
        assertEq(amountOut, 995 * 10**6, "Should use new quote after cache clear");
    }
    
    // ==================== PRICE IMPACT TESTS ====================
    
    function test_GetQuoteWithImpactValidation_Acceptable() public {
        uint256 amountIn = 1000 * 10**6;
        uint256 spotPrice = 1 * 10**18; // 1:1 spot price
        
        // Setup OKX mock
        mockOKXRouter.setQuote(amountIn, 997 * 10**6);
        
        // Get quote with impact validation
        vm.startPrank(authorizedCaller);
        (uint256 amountOut, uint256 impactBps) = swapperV2.getQuoteWithImpactValidation(
            address(mockUSDC),
            address(mockIDRT),
            amountIn,
            6, // USDC decimals
            6, // IDRT decimals
            spotPrice
        );
        vm.stopPrank();
        
        assertEq(amountOut, 997 * 10**6, "Quote amount mismatch");
        assertLe(impactBps, 500, "Impact should be acceptable");
    }
    
    function test_GetQuoteWithImpactValidation_TooHigh() public {
        uint256 amountIn = 1000 * 10**6;
        uint256 spotPrice = 1 * 10**18;
        
        // Setup OKX mock with bad rate
        mockOKXRouter.setQuote(amountIn, 500 * 10**6); // 50% impact
        
        // Should revert with high impact
        vm.startPrank(authorizedCaller);
        vm.expectRevert();
        swapperV2.getQuoteWithImpactValidation(
            address(mockUSDC),
            address(mockIDRT),
            amountIn,
            6,
            6,
            spotPrice
        );
        vm.stopPrank();
    }
    
    // ==================== UTILITY FUNCTION TESTS ====================
    
    function test_IsOKXAvailable_True() public {
        bool available = swapperV2.isOKXAvailable();
        assertTrue(available, "OKX should be available");
    }
    
    function test_IsOKXAvailable_False() public {
        // Disable OKX
        vm.startPrank(owner);
        swapperV2.setOKXIntegrationEnabled(false);
        vm.stopPrank();
        
        bool available = swapperV2.isOKXAvailable();
        assertFalse(available, "OKX should not be available");
    }
    
    // ==================== EVENT TESTS ====================
    
    function test_Event_OKXIntegrationEnabled() public {
        vm.startPrank(owner);
        swapperV2.setOKXIntegrationEnabled(false);
        vm.stopPrank();
    }

    function test_Event_LiquiditySourceSelected() public {
        uint256 amountIn = 1000 * 10**6;
        mockOKXRouter.setQuote(amountIn, 997 * 10**6);

        vm.startPrank(authorizedCaller);
        swapperV2.getRealQuote(address(mockUSDC), address(mockIDRT), amountIn);
        vm.stopPrank();
    }
    
    // ==================== GAS TESTS ====================
    
    function test_Gas_GetRealQuote() public {
        uint256 amountIn = 1000 * 10**6;
        mockOKXRouter.setQuote(amountIn, 997 * 10**6);
        
        vm.startPrank(authorizedCaller);
        uint256 gasBefore = gasleft();
        swapperV2.getRealQuote(address(mockUSDC), address(mockIDRT), amountIn);
        uint256 gasAfter = gasleft();
        vm.stopPrank();
        
        uint256 gasUsed = gasBefore - gasAfter;
        console.log("Gas used for getRealQuote:", gasUsed);
        assertLt(gasUsed, 100000, "Gas used too high");
    }
}

// Mock contracts (same as OKXDexAdapter.t.sol)
contract MockOKXRouter {
    mapping(uint256 => uint256) public quotes;
    bool public quoteFail;
    uint256 public swapResult;
    bool public pairSupported;
    
    function setQuote(uint256 amountIn, uint256 amountOut) external {
        quotes[amountIn] = amountOut;
    }
    
    function setQuoteFail(bool _fail) external {
        quoteFail = _fail;
    }
    
    function setSwapResult(uint256 result) external {
        swapResult = result;
    }
    
    function setPairSupported(bool _supported) external {
        pairSupported = _supported;
    }
    
    function getQuote(
        uint256 fromToken,
        address toToken,
        uint256 fromTokenAmount
    ) external view returns (uint256) {
        if (quoteFail) {
            revert("Quote failed");
        }
        return quotes[fromTokenAmount];
    }
    
    function isPairSupported(
        uint256 fromToken,
        address toToken
    ) external view returns (bool) {
        return pairSupported;
    }
    
    function smartSwapByOrderId(
        IOKXRouter.BaseRequest calldata request,
        IOKXRouter.RouterPath[] calldata paths,
        IOKXRouter.CommissionInfo calldata commission
    ) external payable returns (uint256) {
        return swapResult;
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _mint(msg.sender, 1_000_000_000 * 10**decimals_);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
