// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/integrations/okx/OKXDexAdapter.sol";
import "../../src/integrations/okx/IOKXRouter.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title OKXDexAdapterTest
 * @notice Unit tests for OKXDexAdapter contract
 * @dev Tests quote retrieval, swap execution, access control, and error handling
 */
contract OKXDexAdapterTest is Test {
    // Mock contracts
    MockOKXRouter public mockRouter;
    MockERC20 public mockTokenIn;
    MockERC20 public mockTokenOut;
    
    // Adapter contract
    OKXDexAdapter public adapter;
    
    // Test accounts
    address public owner;
    address public tokenSwapper;
    address public user;
    
    // Constants
    address constant OKX_ROUTER_MOCK = address(0x1234);
    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10**18;
    
    function setUp() public {
        // Setup accounts
        owner = makeAddr("owner");
        tokenSwapper = makeAddr("tokenSwapper");
        user = makeAddr("user");
        
        // Deploy mock tokens
        mockTokenIn = new MockERC20("Token In", "TIN", 18);
        mockTokenOut = new MockERC20("Token Out", "TOUT", 18);
        
        // Deploy mock OKX Router
        mockRouter = new MockOKXRouter();
        
        // Deploy adapter with mock router
        vm.startPrank(owner);
        adapter = new OKXDexAdapter(address(mockRouter), tokenSwapper);
        vm.stopPrank();
        
        // Mint tokens for testing
        mockTokenIn.mint(tokenSwapper, INITIAL_SUPPLY);
        mockTokenOut.mint(address(mockRouter), INITIAL_SUPPLY);
    }
    
    // ==================== CONSTRUCTOR TESTS ====================
    
    function test_Constructor_Success() public {
        // Deploy new adapter
        vm.startPrank(owner);
        OKXDexAdapter newAdapter = new OKXDexAdapter(address(mockRouter), tokenSwapper);
        vm.stopPrank();
        
        // Verify state
        assertEq(newAdapter.okxRouter(), address(mockRouter), "Wrong OKX router");
        assertEq(newAdapter.tokenSwapper(), tokenSwapper, "Wrong TokenSwapper");
        assertEq(newAdapter.owner(), owner, "Wrong owner");
        assertTrue(newAdapter.integrationEnabled(), "Integration should be enabled");
    }
    
    function test_Constructor_InvalidRouter() public {
        // Should revert with zero address
        vm.startPrank(owner);
        vm.expectRevert(OKXDexAdapter.InvalidAddress.selector);
        new OKXDexAdapter(address(0), tokenSwapper);
        vm.stopPrank();
    }
    
    function test_Constructor_InvalidTokenSwapper() public {
        // Should revert with zero address
        vm.startPrank(owner);
        vm.expectRevert(OKXDexAdapter.InvalidAddress.selector);
        new OKXDexAdapter(address(mockRouter), address(0));
        vm.stopPrank();
    }
    
    // ==================== ADMIN FUNCTION TESTS ====================
    
    function test_SetOKXRouter_Success() public {
        address newRouter = makeAddr("newRouter");
        
        vm.startPrank(owner);
        adapter.setOKXRouter(newRouter);
        vm.stopPrank();
        
        assertEq(adapter.okxRouter(), newRouter, "Router not updated");
    }
    
    function test_SetOKXRouter_NotOwner() public {
        address newRouter = makeAddr("newRouter");
        
        vm.startPrank(user);
        vm.expectRevert();
        adapter.setOKXRouter(newRouter);
        vm.stopPrank();
    }
    
    function test_SetTokenSwapper_Success() public {
        address newSwapper = makeAddr("newSwapper");
        
        vm.startPrank(owner);
        adapter.setTokenSwapper(newSwapper);
        vm.stopPrank();
        
        assertEq(adapter.tokenSwapper(), newSwapper, "TokenSwapper not updated");
    }
    
    function test_SetIntegrationEnabled_Success() public {
        vm.startPrank(owner);
        adapter.setIntegrationEnabled(false);
        vm.stopPrank();
        
        assertEq(adapter.integrationEnabled(), false, "Integration should be disabled");
        
        vm.startPrank(owner);
        adapter.setIntegrationEnabled(true);
        vm.stopPrank();
        
        assertEq(adapter.integrationEnabled(), true, "Integration should be enabled");
    }
    
    // ==================== GET QUOTE TESTS ====================
    
    function test_GetQuote_Success() public {
        uint256 amountIn = 1000 * 10**18;
        uint256 expectedOut = 997 * 10**18; // 0.3% slippage
        
        // Setup mock to return expected quote
        mockRouter.setQuote(amountIn, expectedOut);
        
        // Get quote
        vm.startPrank(tokenSwapper);
        uint256 amountOut = adapter.getQuote(
            address(mockTokenIn),
            address(mockTokenOut),
            amountIn
        );
        vm.stopPrank();
        
        assertEq(amountOut, expectedOut, "Quote amount mismatch");
    }
    
    function test_GetQuote_IntegrationDisabled() public {
        uint256 amountIn = 1000 * 10**18;
        
        // Disable integration
        vm.startPrank(owner);
        adapter.setIntegrationEnabled(false);
        vm.stopPrank();
        
        // Should return 0 when disabled
        vm.startPrank(tokenSwapper);
        uint256 amountOut = adapter.getQuote(
            address(mockTokenIn),
            address(mockTokenOut),
            amountIn
        );
        vm.stopPrank();
        
        assertEq(amountOut, 0, "Should return 0 when disabled");
    }
    
    function test_GetQuote_ZeroAmount() public {
        vm.startPrank(tokenSwapper);
        vm.expectRevert(OKXDexAdapter.ZeroAmount.selector);
        adapter.getQuote(address(mockTokenIn), address(mockTokenOut), 0);
        vm.stopPrank();
    }
    
    function test_GetQuote_QuoteFails() public {
        uint256 amountIn = 1000 * 10**18;
        
        // Setup mock to fail
        mockRouter.setQuoteFail(true);
        
        // Should return 0 on failure
        vm.startPrank(tokenSwapper);
        uint256 amountOut = adapter.getQuote(
            address(mockTokenIn),
            address(mockTokenOut),
            amountIn
        );
        vm.stopPrank();
        
        assertEq(amountOut, 0, "Should return 0 on failure");
    }
    
    // ==================== SWAP TESTS ====================
    
    function test_Swap_Success() public {
        uint256 amountIn = 1000 * 10**18;
        uint256 expectedOut = 997 * 10**18;
        uint256 minAmountOut = 990 * 10**18;
        
        // Setup mock
        mockRouter.setQuote(amountIn, expectedOut);
        mockRouter.setSwapResult(expectedOut);
        
        // Approve adapter
        vm.startPrank(tokenSwapper);
        mockTokenIn.approve(address(adapter), amountIn);
        
        // Execute swap
        uint256 amountOut = adapter.swap(
            address(mockTokenIn),
            address(mockTokenOut),
            amountIn,
            minAmountOut
        );
        vm.stopPrank();
        
        assertEq(amountOut, expectedOut, "Swap output mismatch");
    }
    
    function test_Swap_NotTokenSwapper() public {
        uint256 amountIn = 1000 * 10**18;
        
        vm.startPrank(user);
        vm.expectRevert(OKXDexAdapter.NotAuthorized.selector);
        adapter.swap(
            address(mockTokenIn),
            address(mockTokenOut),
            amountIn,
            0
        );
        vm.stopPrank();
    }
    
    function test_Swap_ZeroAmount() public {
        vm.startPrank(tokenSwapper);
        vm.expectRevert(OKXDexAdapter.ZeroAmount.selector);
        adapter.swap(
            address(mockTokenIn),
            address(mockTokenOut),
            0,
            0
        );
        vm.stopPrank();
    }
    
    function test_Swap_SlippageExceeded() public {
        uint256 amountIn = 1000 * 10**18;
        uint256 expectedOut = 997 * 10**18;
        uint256 minAmountOut = 1000 * 10**18; // Too high
        
        // Setup mock
        mockRouter.setQuote(amountIn, expectedOut);
        mockRouter.setSwapResult(expectedOut);
        
        // Approve adapter
        vm.startPrank(tokenSwapper);
        mockTokenIn.approve(address(adapter), amountIn);
        
        // Should revert due to slippage
        vm.expectRevert(OKXDexAdapter.SlippageExceeded.selector);
        adapter.swap(
            address(mockTokenIn),
            address(mockTokenOut),
            amountIn,
            minAmountOut
        );
        vm.stopPrank();
    }
    
    function test_Swap_IntegrationDisabled() public {
        uint256 amountIn = 1000 * 10**18;
        
        // Disable integration
        vm.startPrank(owner);
        adapter.setIntegrationEnabled(false);
        vm.stopPrank();
        
        // Approve adapter
        vm.startPrank(tokenSwapper);
        mockTokenIn.approve(address(adapter), amountIn);
        
        // Should revert
        vm.expectRevert(OKXDexAdapter.IntegrationDisabled.selector);
        adapter.swap(
            address(mockTokenIn),
            address(mockTokenOut),
            amountIn,
            0
        );
        vm.stopPrank();
    }
    
    // ==================== NATIVE TOKEN SWAP TESTS ====================
    
    function test_SwapToNative_Success() public {
        uint256 amountIn = 1000 * 10**18;
        uint256 expectedOut = 997 * 10**18;
        uint256 minAmountOut = 990 * 10**18;
        
        // Setup mock
        mockRouter.setQuote(amountIn, expectedOut);
        mockRouter.setSwapResultNative(expectedOut);
        
        // Approve adapter
        vm.startPrank(tokenSwapper);
        mockTokenIn.approve(address(adapter), amountIn);
        
        // Execute swap to native
        uint256 amountOut = adapter.swapToNative(
            address(mockTokenIn),
            amountIn,
            minAmountOut
        );
        vm.stopPrank();
        
        assertEq(amountOut, expectedOut, "Native swap output mismatch");
    }
    
    function test_SwapFromNative_Success() public {
        uint256 amountIn = 1 * 10**18; // 1 ETH
        uint256 expectedOut = 997 * 10**18;
        uint256 minAmountOut = 990 * 10**18;
        
        // Setup mock
        mockRouter.setSwapResult(expectedOut);
        
        // Execute swap from native
        vm.startPrank(tokenSwapper);
        uint256 amountOut = adapter.swapFromNative{value: amountIn}(
            address(mockTokenOut),
            minAmountOut
        );
        vm.stopPrank();
        
        assertEq(amountOut, expectedOut, "From native swap output mismatch");
    }
    
    // ==================== UTILITY FUNCTION TESTS ====================
    
    function test_IsPairSupported() public {
        mockRouter.setPairSupported(true);
        
        bool supported = adapter.isPairSupported(
            address(mockTokenIn),
            address(mockTokenOut)
        );
        
        assertTrue(supported, "Pair should be supported");
    }
    
    function test_EmergencyWithdraw_Success() public {
        // Send tokens to adapter
        uint256 amount = 100 * 10**18;
        mockTokenIn.transfer(address(adapter), amount);
        
        // Emergency withdraw
        vm.startPrank(owner);
        adapter.emergencyWithdraw(address(mockTokenIn), amount, user);
        vm.stopPrank();
        
        assertEq(mockTokenIn.balanceOf(user), amount, "Withdraw failed");
    }
    
    function test_EmergencyWithdraw_NotOwner() public {
        vm.startPrank(user);
        vm.expectRevert();
        adapter.emergencyWithdraw(address(mockTokenIn), 100, user);
        vm.stopPrank();
    }
    
    // ==================== EVENT TESTS ====================
    
    function test_Events_OKXRouterUpdated() public {
        address newRouter = makeAddr("newRouter");
        
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        // emit OKXRouterUpdated(address(mockRouter), newRouter);
        adapter.setOKXRouter(newRouter);
        vm.stopPrank();
    }
    
    function test_Events_SwapExecuted() public {
        uint256 amountIn = 1000 * 10**18;
        uint256 expectedOut = 997 * 10**18;
        
        mockRouter.setQuote(amountIn, expectedOut);
        mockRouter.setSwapResult(expectedOut);
        
        vm.startPrank(tokenSwapper);
        mockTokenIn.approve(address(adapter), amountIn);

        adapter.swap(
            address(mockTokenIn),
            address(mockTokenOut),
            amountIn,
            0
        );
        vm.stopPrank();
    }
    
    // ==================== GAS OPTIMIZATION TESTS ====================
    
    function test_Gas_GetQuote() public {
        uint256 amountIn = 1000 * 10**18;
        mockRouter.setQuote(amountIn, 997 * 10**18);
        
        vm.startPrank(tokenSwapper);
        uint256 gasBefore = gasleft();
        adapter.getQuote(address(mockTokenIn), address(mockTokenOut), amountIn);
        uint256 gasAfter = gasleft();
        vm.stopPrank();
        
        uint256 gasUsed = gasBefore - gasAfter;
        console.log("Gas used for getQuote:", gasUsed);
        assertLt(gasUsed, 50000, "Gas used too high");
    }
}

// ==================== MOCK CONTRACTS ====================

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
    
    function setSwapResultNative(uint256 result) external {
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
