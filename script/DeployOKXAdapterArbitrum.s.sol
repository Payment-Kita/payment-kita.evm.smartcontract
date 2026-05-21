// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/integrations/okx/OKXDexAdapter.sol";

/**
 * @title DeployOKXAdapterArbitrum
 * @notice Deploy OKX DEX Adapter to Arbitrum chain
 * @dev Hardcoded existing contracts from CHAIN_ARBITRUM.md
 */
contract DeployOKXAdapterArbitrum is Script {
    // ========== HARDCODED FROM CHAIN_ARBITRUM.md + OKX DOCS ==========
    address constant EXISTING_TOKEN_SWAPPER = 0xD12200745Fbb85f37F439DC81F5a649FF131C675;
    address constant EXISTING_GATEWAY = 0x256F96f965eb536E0d6684b0BC52a300663f505a;
    
    // OKX Router - FROM OFFICIAL OKX DOCUMENTATION
    address constant OKX_ROUTER_ARBITRUM = 0x368E01160C2244B0363a35B3fF0A971E44a89284;

    function run() external {
        console.log("+=================================================+");
        console.log("|     OKX Adapter Deployment - ARBITRUM           |");
        console.log("+=================================================+");
        console.log("");
        console.log("Existing Contracts:");
        console.log("  TokenSwapper:", EXISTING_TOKEN_SWAPPER);
        console.log("  Gateway:", EXISTING_GATEWAY);
        console.log("");

        console.log("[DEPLOY] Deploying OKX DEX Adapter...");
        vm.startBroadcast();

        OKXDexAdapter adapter = new OKXDexAdapter(
            OKX_ROUTER_ARBITRUM,
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
        console.log("  OKX Router:", OKX_ROUTER_ARBITRUM);
        console.log("  Status: [OK] Configured from OKX documentation");
        console.log("");
        console.log("Next Steps:");
        console.log("  1. Update CHAIN_ARBITRUM.md with deployed address");
        console.log("  2. OKX Router already configured!");
        console.log("  3. Test OKX integration");
        console.log("");
        console.log("+=================================================+");
        console.log("|              [OK] Deployment Complete!          |");
        console.log("+=================================================+");
    }
}
