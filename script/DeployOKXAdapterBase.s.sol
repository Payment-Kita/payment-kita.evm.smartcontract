// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/integrations/okx/OKXDexAdapter.sol";

/**
 * @title DeployOKXAdapterBase
 * @notice Deploy OKX DEX Adapter to Base chain
 * @dev Hardcoded existing contracts from CHAIN_BASE.md
 */
contract DeployOKXAdapterBase is Script {
    // ========== HARDCODED FROM CHAIN_BASE.md + OKX DOCS ==========
    address constant EXISTING_TOKEN_SWAPPER = 0x8B6c7770D4B8AaD2d600e0cf5df3Eea5Bc0EB0fe;
    address constant EXISTING_GATEWAY = 0xc1d4Ed499417B560A5Df53bA5e2b1A54755Ce58C;
    
    // OKX Router - FROM OFFICIAL OKX DOCUMENTATION
    address constant OKX_ROUTER_BASE = 0x4409921Ae43a39a11D90F7B7F96cfd0B8093d9fC;

    function run() external {
        console.log("+=================================================+");
        console.log("|     OKX Adapter Deployment - BASE               |");
        console.log("+=================================================+");
        console.log("");
        console.log("Existing Contracts:");
        console.log("  TokenSwapper:", EXISTING_TOKEN_SWAPPER);
        console.log("  Gateway:", EXISTING_GATEWAY);
        console.log("");

        console.log("[DEPLOY] Deploying OKX DEX Adapter...");
        vm.startBroadcast();

        OKXDexAdapter adapter = new OKXDexAdapter(
            OKX_ROUTER_BASE,
            EXISTING_GATEWAY
        );

        vm.stopBroadcast();

        address adapterAddress = address(adapter);

        console.log("");
        console.log("[OK] OKX DEX Adapter deployed:", adapterAddress);
        console.log("");
        console.log("+=================================================+");
        console.log("|           Deployment Summary                    |");
        console.log("+=================================================+");
        console.log("");
        console.log("New Contracts:");
        console.log("  OKXDexAdapter:", adapterAddress);
        console.log("");
        console.log("Existing Contracts:");
        console.log("  TokenSwapper:", EXISTING_TOKEN_SWAPPER);
        console.log("  Gateway:", EXISTING_GATEWAY);
        console.log("");
        console.log("Configuration:");
        console.log("  OKX Router:", OKX_ROUTER_BASE);
        console.log("  Status: [OK] Configured from OKX documentation");
        console.log("");
        console.log("Next Steps:");
        console.log("  1. Update CHAIN_BASE.md with deployed address");
        console.log("  2. OKX Router already configured!");
        console.log("  3. Test OKX integration");
        console.log("");
        console.log("+=================================================+");
        console.log("|              [OK] Deployment Complete!          |");
        console.log("+=================================================+");
    }
}
