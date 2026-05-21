// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/integrations/okx/OKXDexAdapter.sol";

/**
 * @title DeployOKXAdapterBSC
 * @notice Deploy OKX DEX Adapter to BSC (Binance Smart Chain)
 * @dev Foundry deployment script for BSC mainnet
 * 
 * Usage:
 * forge script script/DeployOKXAdapterBSC.s.sol:DeployOKXAdapterBSC \
 *   --rpc-url bsc \
 *   --broadcast \
 *   --verify \
 *   --etherscan-api-key $BSCSCAN_API_KEY \
 *   -vvv
 */
contract DeployOKXAdapterBSC is Script {
    // OKX DEX Router on BSC (VERIFY ACTUAL ADDRESS!)
    address constant OKX_ROUTER_BSC = 0x4409921Ae43a39a11D90F7B7F96cfd0B8093d9fC;
    
    function run() external {
        // Get TokenSwapper address from environment
        address tokenSwapper = vm.envAddress("TOKEN_SWAPPER_ADDRESS_BSC");
        
        console.log("Deploying OKXDexAdapter to BSC...");
        console.log("OKX Router:", OKX_ROUTER_BSC);
        console.log("TokenSwapper:", tokenSwapper);
        
        // Deploy OKXDexAdapter
        vm.startBroadcast();
        
        OKXDexAdapter adapter = new OKXDexAdapter(
            OKX_ROUTER_BSC,
            tokenSwapper
        );
        
        vm.stopBroadcast();
        
        address adapterAddress = address(adapter);
        
        console.log("\nOK OKXDexAdapter deployed to:", adapterAddress);
        
        // Log deployment info
        console.log("\nSummary: Deployment Summary:");
        console.log("");
        console.log("Network: BSC (Binance Smart Chain)");
        console.log("Contract: OKXDexAdapter");
        console.log("Address:", adapterAddress);
        console.log("OKX Router:", OKX_ROUTER_BSC);
        console.log("TokenSwapper:", tokenSwapper);
        console.log("");
    }
}
