// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/integrations/okx/OKXDexAdapter.sol";

/**
 * @title DeployOKXAdapterPolygon
 * @notice Deploy OKX DEX Adapter to Polygon chain
 * @dev Hardcoded existing contracts from CHAIN_POLYGON.md
 */
contract DeployOKXAdapterPolygon is Script {
    // ========== HARDCODED FROM CHAIN_POLYGON.md + OKX DOCS ==========
    address constant EXISTING_TOKEN_SWAPPER = 0xe50BDD9CA4289CfD675240B3A7294035655AF8d2;
    address constant EXISTING_GATEWAY = 0xC2Df6CbFeA8c00f7Dacf08B27124cC4fB72f3B69;
    
    // OKX Router - FROM OFFICIAL OKX DOCUMENTATION
    address constant OKX_ROUTER_POLYGON = 0x057cFd839AA88994d1A8A8C6D336CF21550F05Ef;

    function run() external {
        console.log("+=================================================+");
        console.log("|     OKX Adapter Deployment - POLYGON            |");
        console.log("+=================================================+");
        console.log("");
        console.log("Existing Contracts:");
        console.log("  TokenSwapper:", EXISTING_TOKEN_SWAPPER);
        console.log("  Gateway:", EXISTING_GATEWAY);
        console.log("");

        console.log("[DEPLOY] Deploying OKX DEX Adapter...");
        vm.startBroadcast();

        OKXDexAdapter adapter = new OKXDexAdapter(
            OKX_ROUTER_POLYGON,
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
        console.log("  OKX Router:", OKX_ROUTER_POLYGON);
        console.log("  Status: [OK] Configured from OKX documentation");
        console.log("");
        console.log("Next Steps:");
        console.log("  1. Update CHAIN_POLYGON.md with deployed address");
        console.log("  2. OKX Router already configured!");
        console.log("  3. Test OKX integration");
        console.log("");
        console.log("+=================================================+");
        console.log("|              [OK] Deployment Complete!          |");
        console.log("+=================================================+");
    }
}
