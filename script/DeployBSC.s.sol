// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./DeployCommon.s.sol";

contract DeployBSC is DeployCommon {
    function run() public {
        address feeRecipient = vm.envAddress("FEE_RECIPIENT_ADDRESS");

        DeploymentConfig memory config = DeploymentConfig({
            ccipRouter: vm.envOr("BSC_CCIP_ROUTER", address(0)),
            hyperbridgeHost: vm.envOr("BSC_HYPERBRIDGE_HOST", address(0)),
            layerZeroEndpointV2: vm.envOr("BSC_LAYERZERO_ENDPOINT_V2", address(0)),
            uniswapUniversalRouter: vm.envOr("BSC_UNIVERSAL_ROUTER", address(0)),
            uniswapPoolManager: vm.envOr("BSC_POOL_MANAGER", address(0)),
            bridgeToken: vm.envOr("BSC_USDC", address(0)),
            feeRecipient: feeRecipient,
            enableSourceSideSwap: vm.envOr("BSC_ENABLE_SOURCE_SIDE_SWAP", vm.envOr("ENABLE_SOURCE_SIDE_SWAP", false))
        });

        console.log("Deploying to BSC...");
        (PaymentKitaGateway gateway, , TokenRegistry registry, TokenSwapper swapper) = deploySystem(config);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        bool strict = strictTokenRegistration();
        address v3Router = vm.envOr("BSC_V3_ROUTER", address(0));
        require(v3Router != address(0), "DEPLOYMENT ERROR: BSC_V3_ROUTER must be set");
        swapper.setV3Router(v3Router);
        require(swapper.swapRouterV3() == v3Router, "DEPLOYMENT ERROR: BSC V3 router mismatch");
        console.log("Configured V3 router:", v3Router);
        require(gateway.privacyModule() != address(0), "DEPLOYMENT ERROR: privacy module missing");
        require(GatewayPrivacyModule(gateway.privacyModule()).authorizedGateway(address(gateway)), "DEPLOYMENT ERROR: privacy auth missing");
        require(swapper.authorizedCallers(address(gateway)), "DEPLOYMENT ERROR: swapper gateway auth missing");
        require(registry.isTokenSupported(config.bridgeToken), "DEPLOYMENT ERROR: bridge token unsupported");

        // 1. Register tokens + decimals
        address usdc = config.bridgeToken;
        address usdt = vm.envOr("BSC_USDT", address(0));
        address wbnb = vm.envOr("BSC_WBNB", address(0));
        address idrx = vm.envOr("BSC_IDRX", address(0));

        uint256 usdcDec = vm.envOr("BSC_USDC_DECIMAL", uint256(0));
        uint256 usdtDec = vm.envOr("BSC_USDT_DECIMAL", uint256(0));
        uint256 wbnbDec = vm.envOr("BSC_WBNB_DECIMAL", uint256(0));
        uint256 idrxDec = vm.envOr("BSC_IDRX_DECIMAL", uint256(0));

        registerTokenWithOptionalDecimals(registry, usdc, usdcDec, true, "BSC_USDC", "BSC_USDC_DECIMAL");
        registerTokenWithOptionalDecimals(registry, usdt, usdtDec, strict, "BSC_USDT", "BSC_USDT_DECIMAL");
        registerTokenWithOptionalDecimals(registry, wbnb, wbnbDec, strict, "BSC_WBNB", "BSC_WBNB_DECIMAL");
        registerTokenWithOptionalDecimals(registry, idrx, idrxDec, strict, "BSC_IDRX", "BSC_IDRX_DECIMAL");

        // 2. Configure V3 Pools on Swapper
        if (usdc != address(0) && usdt != address(0)) {
            swapper.setV3Pool(usdc, usdt, 100);
            console.log("Configured USDC/USDT V3 pool");
        }
        if (usdc != address(0) && wbnb != address(0)) {
            swapper.setV3Pool(usdc, wbnb, 500);
            console.log("Configured USDC/WBNB V3 pool");
        }
        if (usdc != address(0) && idrx != address(0)) {
            swapper.setV3Pool(usdc, idrx, 100);
            console.log("Configured USDC/IDRX V3 pool");
        }

        // ========== DEPLOY TOKENSWAPPER V3 ==========
        console.log("Deploying TokenSwapperV3...");
        address okxAdapterAddr = vm.envOr("BSC_OKX_ADAPTER", address(0));
        
        if (okxAdapterAddr == address(0)) {
            console.log("Deploying OKX DEX Adapter...");
            OKXDexAdapter okxAdapter = new OKXDexAdapter(
                address(0),
                address(swapper)
            );
            okxAdapterAddr = address(okxAdapter);
            console.log("OKX DEX Adapter deployed:", okxAdapterAddr);
        }
        
        TokenSwapperV3 swapperV3 = new TokenSwapperV3(
            config.uniswapUniversalRouter,
            config.uniswapPoolManager,
            config.bridgeToken,
            okxAdapterAddr
        );
        console.log("TokenSwapperV3 deployed:", address(swapperV3));
        
        vm.startBroadcast(deployerPrivateKey);
        swapperV3.setMaxPriceImpactBps(500);
        swapperV3.setMaxOracleDeviationBps(500);
        swapperV3.setQuoteCacheValidity(30);
        swapperV3.setOKXIntegrationEnabled(true);
        swapperV3.setSplitSwapEnabled(true);
        swapperV3.setOracleValidationEnabled(true);
        console.log("TokenSwapperV3 configured");
        
        // Register tokens in V3
        registerTokenWithOptionalDecimals(registry, usdc, usdcDec, true, "BSC_USDC", "BSC_USDC_DECIMAL");
        registerTokenWithOptionalDecimals(registry, usdt, usdtDec, strict, "BSC_USDT", "BSC_USDT_DECIMAL");
        registerTokenWithOptionalDecimals(registry, idrx, idrxDec, strict, "BSC_IDRX", "BSC_IDRX_DECIMAL");
        console.log("Tokens registered in V3");
        
        // Configure V3 pools on TokenSwapperV3
        if (usdc != address(0) && usdt != address(0)) {
            swapperV3.setV3Pool(usdc, usdt, 100);
            console.log("Configured USDC/USDT V3 pool in V3");
        }
        if (usdc != address(0) && wbnb != address(0)) {
            swapperV3.setV3Pool(usdc, wbnb, 500);
            console.log("Configured USDC/WBNB V3 pool in V3");
        }
        if (usdc != address(0) && idrx != address(0)) {
            swapperV3.setV3Pool(usdc, idrx, 100);
            console.log("Configured USDC/IDRX V3 pool in V3");
        }
        
        // Configure Chainlink oracles
        address usdcOracle = vm.envOr("BSC_USDC_ORACLE", address(0));
        address bnbOracle = vm.envOr("BSC_BNB_ORACLE", address(0));
        
        if (usdcOracle != address(0)) {
            swapperV3.setTokenOracle(usdc, usdcOracle, 3600, 50000000, 150000000);
            console.log("Configured USDC oracle:", usdcOracle);
        }
        
        if (bnbOracle != address(0) && wbnb != address(0)) {
            swapperV3.setTokenOracle(wbnb, bnbOracle, 3600, 100000000000, 10000000000000);
            console.log("Configured WBNB oracle:", bnbOracle);
        }
        
        // Authorize Gateway
        if (address(gateway) != address(0)) {
            swapperV3.setAuthorizedCaller(address(gateway), true);
            console.log("Authorized Gateway to call TokenSwapperV3");
        }
        
        vm.stopBroadcast();
        console.log("TokenSwapperV3 deployment and configuration complete.");
        console.log("TokenSwapperV3:", address(swapperV3));
        console.log("OKX Adapter:", okxAdapterAddr);

        vm.stopBroadcast();
        console.log("Deployment and configuration on BSC complete.");
    }
}
