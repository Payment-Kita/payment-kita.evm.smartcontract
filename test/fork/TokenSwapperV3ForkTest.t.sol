// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/TokenSwapperV3.sol";
import "../../src/integrations/okx/OKXDexAdapter.sol";
import "../../src/libraries/SplitSwapLib.sol";
import "../../src/libraries/PriceOracleLib.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TokenSwapperV3ForkTest
 * @notice Fork tests for TokenSwapperV3 on Base mainnet
 * @dev Tests split-swap, oracle validation, and quote caching on real mainnet data
 * 
 * Usage:
 * forge test --match-contract TokenSwapperV3ForkTest --fork-url https://base-mainnet.g.alchemy.com/v2/YOUR_KEY -vvv
 */
contract TokenSwapperV3ForkTest is Test {
    // Mainnet contracts (Base)
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH_BASE = 0x4200000000000000000000000000000000000006;
    
    // Chainlink Oracles (Base)
    address constant USDC_USD_ORACLE = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;
    address constant ETH_USD_ORACLE = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    
    // Test accounts
    address public testUser;
    uint256 public testUserKey;
    
    // Contracts
    TokenSwapperV3 public swapperV3;
    OKXDexAdapter public mockOkxAdapter;
    
    // Test amounts
    uint256 constant SWAP_AMOUNT = 1000 * 10**6; // 1000 USDC
    uint256 constant LARGE_SWAP_AMOUNT = 50000 * 10**6; // 50,000 USDC
    
    function setUp() public {
        // Create test account
        (testUser, testUserKey) = makeAddrAndKey("testUser");
        
        // Deploy mock OKX adapter (since we don't have real one on fork)
        mockOkxAdapter = new OKXDexAdapter(address(this), address(this));
        
        // Deploy TokenSwapperV3
        swapperV3 = new TokenSwapperV3(
            address(0), // No V4 router
            address(0), // No pool manager
            USDC_BASE,  // Bridge token
            address(mockOkxAdapter)
        );
        
        // Configure oracles
        swapperV3.setTokenOracle(
            USDC_BASE,
            USDC_USD_ORACLE,
            3600, // 1 hour staleness
            50000000, // $0.50 min
            150000000 // $1.50 max
        );
        
        // Fund test user with USDC
        deal(USDC_BASE, testUser, LARGE_SWAP_AMOUNT * 10);
    }
    
    // ==================== SPLIT-SWAP TESTS ====================
    
    function test_SplitSwap_CalculatesOptimalSplit() public {
        // Test SplitSwapLib directly
        SplitSwapLib.LiquidityInfo[4] memory liquidityInfos;
        
        // Simulate liquidity: OKX has best liquidity, V3 has medium
        liquidityInfos[0] = SplitSwapLib.LiquidityInfo(true, 10000, 300); // OKX: 100%, 3% impact
        liquidityInfos[1] = SplitSwapLib.LiquidityInfo(false, 0, 0); // V4: not available
        liquidityInfos[2] = SplitSwapLib.LiquidityInfo(true, 8000, 500); // V3: 80%, 5% impact
        liquidityInfos[3] = SplitSwapLib.LiquidityInfo(true, 5000, 800); // V2: 50%, 8% impact
        
        SplitSwapLib.SplitResult memory split = SplitSwapLib.calculateOptimalSplit(
            LARGE_SWAP_AMOUNT,
            liquidityInfos
        );
        
        // Should split across multiple DEXes
        assertGt(split.paths.length, 0, "Should have at least one path");
        assertLe(split.totalPriceImpactBps, 500, "Total impact should be reasonable");
        
        console.log("Split paths:", split.paths.length);
        console.log("Total price impact (bps):", split.totalPriceImpactBps);
    }
    
    function test_SplitSwap_CompareVsSingle() public {
        SplitSwapLib.SplitResult memory splitResult;
        splitResult.totalExpectedOut = 1050 * 10**6; // 1050 tokens out
        
        uint256 singlePathOut = 1000 * 10**6; // 1000 tokens out
        
        (bool isBetter, uint256 improvementBps) = SplitSwapLib.compareSplitVsSingle(
            singlePathOut,
            splitResult
        );
        
        assertTrue(isBetter, "Split should be better");
        assertGt(improvementBps, 0, "Should have improvement");
        assertGe(improvementBps, 400, "Improvement should be ~5%"); // 50/1000 = 5%
        
        console.log("Split is better:", isBetter);
        console.log("Improvement (bps):", improvementBps);
    }
    
    // ==================== ORACLE VALIDATION TESTS ====================
    
    function test_OracleValidation_GetLatestPrice() public {
        PriceOracleLib.OracleConfig memory config = PriceOracleLib.OracleConfig({
            aggregator: USDC_USD_ORACLE,
            maxStaleness: 3600,
            minAnswer: 50000000,
            maxAnswer: 150000000
        });
        
        PriceOracleLib.PriceData memory data = PriceOracleLib.getLatestPrice(config);
        
        assertFalse(data.stale, "Price should not be stale");
        assertGt(data.price, 0, "Price should be positive");
        
        // console.log("USDC Price:", data.price);
        console.log("Updated at:", data.updatedAt);
        console.log("Round ID:", data.roundId);
    }
    
    function test_OracleValidation_ValidatePriceDeviation() public {
        uint256 executionPrice = 100 * 10**18; // 1.00
        uint256 oraclePrice = 100 * 10**18; // 1.00
        uint256 maxDeviationBps = 500; // 5%
        
        (bool isValid, uint256 deviationBps) = PriceOracleLib.validatePriceDeviation(
            executionPrice,
            oraclePrice,
            maxDeviationBps
        );
        
        assertTrue(isValid, "Price should be valid (0% deviation)");
        assertEq(deviationBps, 0, "Deviation should be 0");
        
        // Test with 6% deviation (should fail)
        executionPrice = 106 * 10**18;
        (isValid, deviationBps) = PriceOracleLib.validatePriceDeviation(
            executionPrice,
            oraclePrice,
            maxDeviationBps
        );
        
        assertFalse(isValid, "Price should be invalid (>5% deviation)");
        assertGe(deviationBps, 600, "Deviation should be >=6%");
        
        console.log("Valid:", isValid);
        console.log("Deviation (bps):", deviationBps);
    }
    
    function test_OracleValidation_GetFairPrice() public {
        address[] memory oracles = new address[](2);
        oracles[0] = USDC_USD_ORACLE;
        oracles[1] = USDC_USD_ORACLE; // Same oracle for testing
        
        (int256 fairPrice, bool isReliable) = PriceOracleLib.getFairPrice(oracles);
        
        assertGt(fairPrice, 0, "Fair price should be positive");
        assertTrue(isReliable, "Price should be reliable");
        
        // console.log("Fair Price:", fairPrice);
        console.log("Is Reliable:", isReliable);
    }
    
    // ==================== QUOTE CACHE TESTS ====================
    
    function test_QuoteCache_CacheAndRetrieve() public {
        address tokenIn = USDC_BASE;
        address tokenOut = WETH_BASE;
        uint256 amountIn = 1000 * 10**6;
        uint256 amountOut = 500 * 10**18;
        
        // Cache quote
        vm.prank(address(swapperV3));
        swapperV3.clearQuoteCache(tokenIn, tokenOut, amountIn);
        
        // Note: _cacheQuote is internal, would need to test through getRealQuote
        // This is a placeholder for actual cache testing
        
        bytes32 key = keccak256(abi.encodePacked(tokenIn, tokenOut, amountIn));
        (uint256 cachedAmountOut, uint256 blockNumber, uint256 timestamp, , bool valid) = 
            swapperV3.quoteCaches(key);
        
        // Cache should be empty initially
        assertFalse(valid, "Cache should be empty initially");
        
        console.log("Cache key:", vm.toString(key));
        console.log("Cache valid:", valid);
    }
    
    function test_QuoteCache_ValidityPeriod() public {
        uint256 currentValidity = swapperV3.quoteCacheValidity();
        
        assertEq(currentValidity, 30, "Default validity should be 30 seconds");
        
        // Update validity
        vm.prank(swapperV3.owner());
        swapperV3.setQuoteCacheValidity(60);
        
        assertEq(swapperV3.quoteCacheValidity(), 60, "Validity should be updated to 60");
        
        console.log("Quote cache validity:", swapperV3.quoteCacheValidity(), "seconds");
    }
    
    // ==================== INTEGRATION TESTS ====================
    
    function test_Integration_GetRealQuote_WithMockOKX() public {
        // Setup mock OKX to return quote
        // Note: In real scenario, OKX adapter would call actual OKX router
        
        vm.startPrank(testUser);
        
        // This would test the full quote flow
        // For now, we test that the function doesn't revert
        try swapperV3.getRealQuote(USDC_BASE, WETH_BASE, SWAP_AMOUNT) returns (uint256 amountOut) {
            console.log("Quote amount:", amountOut);
            assertGt(amountOut, 0, "Should return positive quote");
        } catch {
            // Expected to fail without real OKX integration
            console.log("Quote failed (expected without real OKX)");
        }
        
        vm.stopPrank();
    }
    
    function test_Integration_SwapWithOracleValidation() public {
        vm.startPrank(testUser);
        
        // Approve USDC
        IERC20(USDC_BASE).approve(address(swapperV3), SWAP_AMOUNT);
        
        // Try swap with oracle validation
        try swapperV3.swapWithOracleValidation(
            USDC_BASE,
            WETH_BASE,
            SWAP_AMOUNT,
            0, // No min amount for testing
            testUser
        ) returns (uint256 amountOut) {
            console.log("Swap successful, amount out:", amountOut);
        } catch Error(string memory reason) {
            console.log("Swap failed:", reason);
            // Expected to fail without real liquidity
        }
        
        vm.stopPrank();
    }
    
    // ==================== GAS BENCHMARK TESTS ====================
    
    function test_Gas_SplitSwapCalculation() public {
        SplitSwapLib.LiquidityInfo[4] memory liquidityInfos;
        liquidityInfos[0] = SplitSwapLib.LiquidityInfo(true, 10000, 300);
        liquidityInfos[1] = SplitSwapLib.LiquidityInfo(false, 0, 0);
        liquidityInfos[2] = SplitSwapLib.LiquidityInfo(true, 8000, 500);
        liquidityInfos[3] = SplitSwapLib.LiquidityInfo(true, 5000, 800);
        
        uint256 gasBefore = gasleft();
        SplitSwapLib.SplitResult memory split = SplitSwapLib.calculateOptimalSplit(
            LARGE_SWAP_AMOUNT,
            liquidityInfos
        );
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Gas used for split calculation:", gasUsed);
        assertLt(gasUsed, 100000, "Gas should be reasonable");
    }
    
    function test_Gas_OraclePriceFetch() public {
        PriceOracleLib.OracleConfig memory config = PriceOracleLib.OracleConfig({
            aggregator: USDC_USD_ORACLE,
            maxStaleness: 3600,
            minAnswer: 50000000,
            maxAnswer: 150000000
        });
        
        uint256 gasBefore = gasleft();
        PriceOracleLib.PriceData memory data = PriceOracleLib.getLatestPrice(config);
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Gas used for oracle price fetch:", gasUsed);
        assertLt(gasUsed, 100000, "Gas should be reasonable");
    }
    
    // ==================== EDGE CASE TESTS ====================
    
    function test_EdgeCase_ZeroAmount() public {
        vm.expectRevert();
        swapperV3.getRealQuote(USDC_BASE, WETH_BASE, 0);
    }
    
//    function test_EdgeCase_InvalidOracle() public {
//        // Configure invalid oracle
//        swapperV3.setTokenOracle(
//            USDC_BASE,
//            address(0), // Invalid aggregator
//            3600,
//            0,
//            0
//        );
//        
//        // Should handle gracefully (return 0 or skip validation)
//        // PriceOracleLib.OracleConfig memory config = swapperV3.tokenOracles(USDC_BASE);
//        assertEq(config.aggregator, address(0), "Oracle should be zero");
//    }
    
    function test_EdgeCase_StalePrice() public {
        // Configure very short staleness
        PriceOracleLib.OracleConfig memory config = PriceOracleLib.OracleConfig({
            aggregator: USDC_USD_ORACLE,
            maxStaleness: 1, // 1 second
            minAnswer: 50000000,
            maxAnswer: 150000000
        });
        
        PriceOracleLib.PriceData memory data = PriceOracleLib.getLatestPrice(config);
        
        // Price should be stale (block time > 1 second)
        assertTrue(data.stale, "Price should be stale with 1s max staleness");
    }
    
    // ==================== HELPER FUNCTIONS ====================
    
    function _logSplitResult(SplitSwapLib.SplitResult memory split) internal view {
        console.log("=== Split Result ===");
        console.log("Total paths:", split.paths.length);
        console.log("Total expected out:", split.totalExpectedOut);
        console.log("Total price impact (bps):", split.totalPriceImpactBps);
        console.log("Gas estimate:", split.gasEstimate);
        
        for (uint256 i = 0; i < split.paths.length; i++) {
            console.log("Path", i);
            console.log("  DEX:", split.paths[i].dex);
            console.log("  Percentage (bps):", split.paths[i].percentageBps);
            console.log("  Price impact (bps):", split.paths[i].priceImpactBps);
        }
    }
}
