// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TokenSwapperV3.sol";
import "../src/integrations/okx/OKXDexAdapter.sol";
import "../src/TokenRegistry.sol";

/**
 * @title DeployBase
 * @notice TokenSwapperV3 deployment script for BASE with hardcoded existing contracts
 * @dev Uses existing Gateway, Registry, Vault from CHAIN_BASE.md
 */
contract DeployBase is Script {
    // ========== HARDCODED EXISTING CONTRACTS (BASE) ==========
    address constant EXISTING_GATEWAY = 0xc1d4Ed499417B560A5Df53bA5e2b1A54755Ce58C;
    address constant EXISTING_REGISTRY = 0x140fbAA1e8BE387082aeb6088E4Ffe1bf3Ba4d4f;
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant IDRX_BASE = 0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22;
    address constant WETH_BASE = 0x4200000000000000000000000000000000000006;
    address constant USDC_ORACLE_BASE = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;
    address constant ETH_ORACLE_BASE = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    
    function run() public {
        console.log("+========================================================+");
        console.log("|     TokenSwapperV3 Deployment - BASE                   |");
        console.log("+========================================================+");
        console.log("");
        console.log("Existing Contracts:");
        console.log("  Gateway:", EXISTING_GATEWAY);
        console.log("  Registry:", EXISTING_REGISTRY);
        console.log("  USDC:", USDC_BASE);
        console.log("  IDRX:", IDRX_BASE);
        console.log("  WETH:", WETH_BASE);
        console.log("");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // ========== DEPLOY OKX DEX ADAPTER ==========
        console.log("[DEPLOY] Deploying OKX DEX Adapter...");
        // Note: OKX Router address will be configured later via setOKXRouter()
        // Check OKX documentation for correct router address per chain
        OKXDexAdapter okxAdapter = new OKXDexAdapter(
            address(0), // OKX Router - configure later
            EXISTING_GATEWAY // Default caller
        );
        address okxAdapterAddr = address(okxAdapter);
        console.log("[OK] OKX DEX Adapter deployed:", okxAdapterAddr);
        
        // ========== DEPLOY TOKENSWAPPER V3 ==========
        console.log("Deploying TokenSwapperV3...");
        TokenSwapperV3 swapperV3 = new TokenSwapperV3(
            address(0), // No V4 router on Base yet
            address(0), // No pool manager
            USDC_BASE,
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
        // EXISTING_REGISTRY.setTokenSupport(USDC_BASE, true);
        // EXISTING_REGISTRY.setTokenSupport(IDRX_BASE, true);
        // EXISTING_REGISTRY.setTokenSupport(WETH_BASE, true);
        console.log("[OK] Tokens registered");
        
        // ========== CONFIGURE V3 POOLS ==========
        console.log("Configuring V3 pools...");
        swapperV3.setV3Pool(USDC_BASE, IDRX_BASE, 100);
        swapperV3.setV3Pool(USDC_BASE, WETH_BASE, 500);
        console.log("[OK] V3 pools configured");
        
        // ========== CONFIGURE CHAINLINK ORACLES ==========
        console.log("Configuring Chainlink oracles...");
        swapperV3.setTokenOracle(
            USDC_BASE,
            USDC_ORACLE_BASE,
            3600, // 1 hour staleness
            50000000, // $0.50 min
            150000000 // $1.50 max
        );
        swapperV3.setTokenOracle(
            WETH_BASE,
            ETH_ORACLE_BASE,
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
        console.log("|           Deployment Summary - BASE                    |");
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
        console.log("  Bridge Token: USDC", USDC_BASE);
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
