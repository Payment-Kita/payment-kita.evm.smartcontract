// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TokenSwapper.sol";
import "../src/PaymentKitaGateway.sol";
import "../src/vaults/PaymentKitaVault.sol";

/**
 * @title FinalizeSwapperArbitrum
 * @notice Script to complete the configuration of the newly deployed TokenSwapper.
 */
contract FinalizeSwapperArbitrum is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        // Use the newly deployed Swapper and existing component addresses (with correct checksums)
        address swapperAddr = 0xD12200745Fbb85f37F439DC81F5a649FF131C675;
        address vaultAddr = 0x4a92d4079853c78dF38B4BbD574AA88679Adef93;
        address gatewayAddr = 0x259294aecdC0006B73b1281c30440A8179CFF44c;
        address v3Router = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

        // Token Addresses
        address usdc = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        address usdt = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
        address xaut = 0x40461291347e1eCbb09499F3371D3f17f10d7159;
        address wbtc = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;

        vm.startBroadcast(pk);

        TokenSwapper swapper = TokenSwapper(swapperAddr);

        // 1. Resume from setV3Router
        console.log("Configuring V3 Router...");
        swapper.setV3Router(v3Router);
        
        // 2. Authorize Gateway on Swapper
        console.log("Authorizing Gateway on Swapper...");
        swapper.setAuthorizedCaller(gatewayAddr, true);

        // 3. Authorize Swapper on Vault
        console.log("Authorizing Swapper on Vault...");
        PaymentKitaVault(vaultAddr).setAuthorizedSpender(swapperAddr, true);

        // 4. Update Gateway to use new Swapper
        console.log("Updating Gateway swapper reference...");
        PaymentKitaGateway(gatewayAddr).setSwapper(swapperAddr);

        // 5. Re-register critical V4 pools
        console.log("Registering V4 pools...");
        swapper.setDirectPool(usdc, usdt, 100, 1, address(0), "");
        swapper.setDirectPool(xaut, usdt, 6000, 120, address(0), "");
        swapper.setDirectPool(wbtc, usdt, 500, 10, address(0), "");

        vm.stopBroadcast();

        console.log("FinalizeSwapperArbitrum completed successfully.");
    }
}
