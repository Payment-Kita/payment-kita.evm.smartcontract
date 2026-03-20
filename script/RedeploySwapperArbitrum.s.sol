// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TokenSwapper.sol";
import "../src/PaymentKitaGateway.sol";
import "../src/vaults/PaymentKitaVault.sol";

/**
 * @title RedeploySwapperArbitrum
 * @notice Script to redeploy TokenSwapper with the V4 settlement fix and rewire it to the Gateway.
 */
contract RedeploySwapperArbitrum is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        // Arbitrum One Addresses
        address universalRouter = 0xA51afAFe0263b40EdaEf0Df8781eA9aa03E381a3;
        address poolManager = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;
        address bridgeToken = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        address vaultAddr = 0x4a92d4079853c78dF38B4BbD574AA88679Adef93;
        address gatewayAddr = 0x259294aecdC0006B73b1281c30440A8179CFF44c;
        address v3Router = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

        // Token Addresses
        address usdc = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        address usdt = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
        address xaut = 0x40461291347e1eCbb09499F3371D3f17f10d7159;
        address wbtc = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;

        vm.startBroadcast(pk);

        console.log("Deploying new TokenSwapper...");
        TokenSwapper swapper = new TokenSwapper(
            universalRouter,
            poolManager,
            bridgeToken
        );
        console.log("New TokenSwapper deployed at:", address(swapper));

        // 1. Initial Configuration
        swapper.setVault(vaultAddr);
        swapper.setV3Router(v3Router);
        
        // 2. Authorize Gateway on Swapper
        swapper.setAuthorizedCaller(gatewayAddr, true);
        console.log("Gateway authorized on Swapper.");

        // 3. Authorize Swapper on Vault
        PaymentKitaVault(vaultAddr).setAuthorizedSpender(address(swapper), true);
        console.log("Swapper authorized on Vault.");

        // 4. Update Gateway to use new Swapper
        PaymentKitaGateway(gatewayAddr).setSwapper(address(swapper));
        console.log("PaymentKitaGateway updated with new Swapper address.");

        // 5. Re-register critical V4 pools (Optional but recommended for consistency)
        // USDC/USDT: fee 100, tick 1
        swapper.setDirectPool(usdc, usdt, 100, 1, address(0), "");
        console.log("Configured USDC/USDT V4 pool (fee 100, tick 1)");

        // XAUT/USDT: fee 6000, tick 120 (FIXED)
        swapper.setDirectPool(xaut, usdt, 6000, 120, address(0), "");
        console.log("Configured XAUT/USDT V4 pool (fee 6000, tick 120)");

        // WBTC/USDT: fee 500, tick 10
        swapper.setDirectPool(wbtc, usdt, 500, 10, address(0), "");
        console.log("Configured WBTC/USDT V4 pool (fee 500, tick 10)");

        vm.stopBroadcast();

        console.log("RedeploySwapperArbitrum completed successfully.");
    }
}
