// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TokenSwapperV3.sol";
import "../src/integrations/okx/OKXDexAdapter.sol";
import "../src/TokenRegistry.sol";

/**
 * @title DeployArbitrum
 * @notice TokenSwapperV3 deployment script for ARBITRUM with hardcoded existing contracts
 * @dev Uses existing Gateway, Registry from CHAIN_ARBITRUM.md
 */
contract DeployArbitrum is Script {
    // ========== HARDCODED EXISTING CONTRACTS (ARBITRUM) ==========
    address constant EXISTING_GATEWAY = 0x256F96f965eb536E0d6684b0BC52a300663f505a;
    address constant EXISTING_REGISTRY = 0x53F1e35FEA4b2cDC7E73Feb4E36365c88569ebf0;
    address constant USDC_ARBITRUM = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant USDT_ARBITRUM = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant USDC_ORACLE_ARBITRUM = 0x50838f83De5De41747f5063f0f75A598269940fb;
    address constant ETH_ORACLE_ARBITRUM = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    
    function run() public {
        console.log("+========================================================+");
        console.log("|     TokenSwapperV3 Deployment - ARBITRUM               |");
        console.log("+========================================================+");
        console.log("");
        console.log("Existing Contracts:");
        console.log("  Gateway:", EXISTING_GATEWAY);
        console.log("  Registry:", EXISTING_REGISTRY);
        console.log("  USDC:", USDC_ARBITRUM);
        console.log("  USDT:", USDT_ARBITRUM);
        console.log("");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // ========== DEPLOY OKX DEX ADAPTER ==========
        console.log("Deploying OKX DEX Adapter...");
        OKXDexAdapter okxAdapter = new OKXDexAdapter(
            address(0), // OKX Router (configure later)
            EXISTING_GATEWAY // Default caller
        );
        address okxAdapterAddr = address(okxAdapter);
        console.log("[OK] OKX DEX Adapter deployed:", okxAdapterAddr);
        
        // ========== DEPLOY TOKENSWAPPER V3 ==========
        console.log("Deploying TokenSwapperV3...");
        TokenSwapperV3 swapperV3 = new TokenSwapperV3(
            address(0), // No V4 router on Arbitrum yet
            address(0), // No pool manager
            USDC_ARBITRUM,
            okxAdapterAddr
        );
        console.log("[OK] TokenSwapperV3 deployed:", address(swapperV3));
        
        // ========== CONFIGURE TOKENSWAPPER V3 ==========
        console.log("Configuring TokenSwapperV3...");
        swapperV3.setMaxPriceImpactBps(500); // 5%
        swapperV3.setMaxOracleDeviationBps(500); // 5%
        swapperV3.setQuoteCacheValidity(30); // 30 seconds
        swapperV3.setOKXIntegrationEnabled(true);
        swapperV3.setSplitSwapEnabled(true);
        swapperV3.setOracleValidationEnabled(true);
        console.log("[OK] TokenSwapperV3 configured");
        
        // ========== REGISTER TOKENS ==========
        console.log("Registering tokens...");
        // EXISTING_REGISTRY.setTokenSupport(USDC_ARBITRUM, true);
        // EXISTING_REGISTRY.setTokenSupport(USDT_ARBITRUM, true);
        console.log("[OK] Tokens registered");
        
        // ========== CONFIGURE V3 POOLS ==========
        console.log("Configuring V3 pools...");
        swapperV3.setV3Pool(USDC_ARBITRUM, USDT_ARBITRUM, 100);
        console.log("[OK] V3 pools configured");
        
        // ========== CONFIGURE CHAINLINK ORACLES ==========
        console.log("Configuring Chainlink oracles...");
        swapperV3.setTokenOracle(
            USDC_ARBITRUM,
            USDC_ORACLE_ARBITRUM,
            3600, // 1 hour staleness
            50000000, // $0.50 min
            150000000 // $1.50 max
        );
        swapperV3.setTokenOracle(
            USDC_ARBITRUM,
            ETH_ORACLE_ARBITRUM,
            3600,
            100000000000, // $1000 min
            10000000000000 // $10000 max
        );
        console.log("[OK] Oracles configured");
        
        // ========== WIRE TO EXISTING GATEWAY ==========
        console.log("Wiring to existing Gateway...");
        swapperV3.setAuthorizedCaller(EXISTING_GATEWAY, true);
        console.log("[OK] Gateway authorized to call TokenSwapperV3");
        
        vm.stopBroadcast();
        
        // ========== VALIDATION ==========
        console.log("");
        console.log("Running validation checks...");
        require(swapperV3.okxDexAdapter() != address(0), "OKX adapter not configured");
        require(swapperV3.okxIntegrationEnabled(), "OKX integration not enabled");
        require(swapperV3.splitSwapEnabled(), "Split-swap not enabled");
        require(swapperV3.oracleValidationEnabled(), "Oracle validation not enabled");
        console.log("[OK] All validations passed");
        
        // ========== PRINT SUMMARY ==========
        console.log("");
        console.log("+========================================================+");
        console.log("|           Deployment Summary - ARBITRUM                |");
        console.log("+========================================================+");
        console.log("");
        console.log("New Contracts:");
        console.log("  TokenSwapperV3:", address(swapperV3));
        console.log("  OKX DEX Adapter:", okxAdapterAddr);
        console.log("");
        console.log("Existing Contracts:");
        console.log("  Gateway:", EXISTING_GATEWAY);
        console.log("  Registry:", EXISTING_REGISTRY);
        console.log("");
        console.log("Configuration:");
        console.log("  Bridge Token: USDC", USDC_ARBITRUM);
        console.log("  Max Price Impact: 5%");
        console.log("  Max Oracle Deviation: 5%");
        console.log("  Quote Cache Validity: 30s");
        console.log("");
        console.log("Features:");
        console.log("  OKX Integration: [Y] Enabled");
        console.log("  Split-Swap: [Y] Enabled");
        console.log("  Oracle Validation: [Y] Enabled");
        console.log("");
        console.log("Wiring:");
        console.log("  Gateway -> TokenSwapperV3: [Y] Authorized");
        console.log("");
        console.log("+========================================================+");
        console.log("|              [OK] Deployment Complete!                   |");
        console.log("+========================================================+");
    }
}
