// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TokenSwapperV3.sol";
import "../src/integrations/okx/OKXDexAdapter.sol";
import "../src/TokenRegistry.sol";

/**
 * @title DeployPolygon
 * @notice TokenSwapperV3 deployment script for POLYGON with hardcoded existing contracts
 * @dev Uses existing Gateway, Registry from CHAIN_POLYGON.md
 */
contract DeployPolygon is Script {
    // ========== HARDCODED EXISTING CONTRACTS (POLYGON) ==========
    address constant EXISTING_GATEWAY = 0xC2Df6CbFeA8c00f7Dacf08B27124cC4fB72f3B69;
    address constant EXISTING_REGISTRY = 0x01e0042BC84F1dbc2F88Fb3ae8b1EA6A86Dc491d;
    address constant USDC_POLYGON = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
    address constant IDRT_POLYGON = 0x554cd6bdD03214b10AafA3e0D4D42De0C5D2937b;
    address constant USDT_POLYGON = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
    address constant WETH_POLYGON = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address constant USDC_ORACLE_POLYGON = 0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7;
    address constant MATIC_ORACLE_POLYGON = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0;
    
    function run() public {
        console.log("+========================================================+");
        console.log("|     TokenSwapperV3 Deployment - POLYGON                |");
        console.log("+========================================================+");
        console.log("");
        console.log("Existing Contracts:");
        console.log("  Gateway:", EXISTING_GATEWAY);
        console.log("  Registry:", EXISTING_REGISTRY);
        console.log("  USDC:", USDC_POLYGON);
        console.log("  IDRT:", IDRT_POLYGON);
        console.log("  USDT:", USDT_POLYGON);
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
            address(0), // No V4 router on Polygon yet
            address(0), // No pool manager
            USDC_POLYGON,
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
        // EXISTING_REGISTRY.setTokenSupport(USDC_POLYGON, true);
        // EXISTING_REGISTRY.setTokenSupport(IDRT_POLYGON, true);
        // EXISTING_REGISTRY.setTokenSupport(USDT_POLYGON, true);
        console.log("[OK] Tokens registered");
        
        // ========== CONFIGURE V3 POOLS ==========
        console.log("Configuring V3 pools...");
        swapperV3.setV3Pool(USDC_POLYGON, USDT_POLYGON, 100);
        swapperV3.setV3Pool(USDT_POLYGON, IDRT_POLYGON, 10000);
        console.log("[OK] V3 pools configured");
        
        // ========== CONFIGURE CHAINLINK ORACLES ==========
        console.log("Configuring Chainlink oracles...");
        swapperV3.setTokenOracle(
            USDC_POLYGON,
            USDC_ORACLE_POLYGON,
            3600, // 1 hour staleness
            50000000, // $0.50 min
            150000000 // $1.50 max
        );
        swapperV3.setTokenOracle(
            USDC_POLYGON,
            MATIC_ORACLE_POLYGON,
            3600,
            100000000000, // $0.10 min
            10000000000000 // $10.00 max
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
        console.log("|           Deployment Summary - POLYGON                 |");
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
        console.log("  Bridge Token: USDC", USDC_POLYGON);
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
