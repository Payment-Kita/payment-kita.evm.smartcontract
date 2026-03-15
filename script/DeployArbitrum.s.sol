// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./DeployCommon.s.sol";

contract DeployArbitrum is DeployCommon {
    function run() public {
        address feeRecipient = vm.envAddress("FEE_RECIPIENT_ADDRESS");

        DeploymentConfig memory config = DeploymentConfig({
            ccipRouter: vm.envOr("ARBITRUM_CCIP_ROUTER", address(0)),
            hyperbridgeHost: vm.envOr("ARBITRUM_HYPERBRIDGE_HOST", address(0)),
            layerZeroEndpointV2: vm.envOr("ARBITRUM_LAYERZERO_ENDPOINT_V2", address(0)),
            uniswapUniversalRouter: vm.envOr("ARBITRUM_UNIVERSAL_ROUTER", address(0)),
            uniswapPoolManager: vm.envOr("ARBITRUM_POOL_MANAGER", address(0)),
            bridgeToken: vm.envOr("ARBITRUM_USDC", address(0)),
            feeRecipient: feeRecipient,
            enableSourceSideSwap: vm.envOr("ARBITRUM_ENABLE_SOURCE_SIDE_SWAP", vm.envOr("ENABLE_SOURCE_SIDE_SWAP", false))
        });

        RouteBootstrapConfig memory routeConfig;
        routeConfig.enabled = vm.envOr("ARBITRUM_ROUTE_BOOTSTRAP_ENABLED", false);
        if (routeConfig.enabled) {
            routeConfig.destCaip2 = vm.envOr("ARBITRUM_ROUTE_DEST_CAIP2", string(""));
            require(bytes(routeConfig.destCaip2).length > 0, "DEPLOYMENT ERROR: ARBITRUM_ROUTE_DEST_CAIP2 must be set");

            routeConfig.defaultBridgeType = _toUint8Checked(vm.envOr("ARBITRUM_ROUTE_DEFAULT_BRIDGE_TYPE", uint256(3)));

            string memory hbStateMachineId = vm.envOr("ARBITRUM_ROUTE_HB_STATE_MACHINE_ID", string(""));
            if (bytes(hbStateMachineId).length > 0) {
                routeConfig.hbStateMachineId = bytes(hbStateMachineId);
            }

            string memory hbDestinationContract = vm.envOr("ARBITRUM_ROUTE_HB_DESTINATION_CONTRACT", string(""));
            if (bytes(hbDestinationContract).length > 0) {
                routeConfig.hbDestinationContract = bytes(hbDestinationContract);
            }
        }

        console.log("Deploying to Arbitrum...");
        (PaymentKitaGateway gateway, , TokenRegistry registry, TokenSwapper swapper) = deploySystem(config, routeConfig);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        bool strict = strictTokenRegistration();
        address v3Router = vm.envOr("ARBITRUM_V3_ROUTER", address(0));
        require(v3Router != address(0), "DEPLOYMENT ERROR: ARBITRUM_V3_ROUTER must be set");
        swapper.setV3Router(v3Router);
        require(swapper.swapRouterV3() == v3Router, "DEPLOYMENT ERROR: ARBITRUM V3 router mismatch");
        console.log("Configured V3 router:", v3Router);
        require(gateway.privacyModule() != address(0), "DEPLOYMENT ERROR: privacy module missing");
        require(GatewayPrivacyModule(gateway.privacyModule()).authorizedGateway(address(gateway)), "DEPLOYMENT ERROR: privacy auth missing");
        require(swapper.authorizedCallers(address(gateway)), "DEPLOYMENT ERROR: swapper gateway auth missing");
        require(registry.isTokenSupported(config.bridgeToken), "DEPLOYMENT ERROR: bridge token unsupported");

        // 1. Register tokens + decimals
        address usdc = config.bridgeToken;
        address usdt = vm.envOr("ARBITRUM_USDT", address(0));
        address dai = vm.envOr("ARBITRUM_DAI", address(0));
        address wbtc = vm.envOr("ARBITRUM_WBTC", address(0));
        address xaut = vm.envOr("ARBITRUM_XAUT", address(0));

        uint256 usdcDec = vm.envOr("ARBITRUM_USDC_DECIMAL", uint256(0));
        uint256 usdtDec = vm.envOr("ARBITRUM_USDT_DECIMAL", uint256(0));
        uint256 daiDec = vm.envOr("ARBITRUM_DAI_DECIMAL", uint256(0));
        uint256 wbtcDec = vm.envOr("ARBITRUM_WBTC_DECIMAL", uint256(0));
        uint256 xautDec = vm.envOr("ARBITRUM_XAUT_DECIMAL", uint256(0));

        registerTokenWithOptionalDecimals(registry, usdc, usdcDec, true, "ARBITRUM_USDC", "ARBITRUM_USDC_DECIMAL");
        registerTokenWithOptionalDecimals(registry, usdt, usdtDec, strict, "ARBITRUM_USDT", "ARBITRUM_USDT_DECIMAL");
        registerTokenWithOptionalDecimals(registry, dai, daiDec, strict, "ARBITRUM_DAI", "ARBITRUM_DAI_DECIMAL");
        registerTokenWithOptionalDecimals(registry, wbtc, wbtcDec, strict, "ARBITRUM_WBTC", "ARBITRUM_WBTC_DECIMAL");
        registerTokenWithOptionalDecimals(registry, xaut, xautDec, strict, "ARBITRUM_XAUT", "ARBITRUM_XAUT_DECIMAL");

        // 2. Configure direct pools on Swapper
        // V4 pools
        address v4Hooks = vm.envOr("ARBITRUM_V4_HOOKS", address(0));
        bytes memory hookData = bytes("");

        uint24 feeUsdcUsdtV4 = uint24(vm.envOr("ARBITRUM_POOL_FEE_USDC_USDT_V4", uint256(100)));
        int24 tickUsdcUsdtV4 = int24(int256(vm.envOr("ARBITRUM_POOL_TICK_USDC_USDT_V4", uint256(1))));
        uint24 feeUsdcWbtcV4 = uint24(vm.envOr("ARBITRUM_POOL_FEE_USDC_WBTC_V4", uint256(500)));
        int24 tickUsdcWbtcV4 = int24(int256(vm.envOr("ARBITRUM_POOL_TICK_USDC_WBTC_V4", uint256(10))));
        uint24 feeUsdtWbtcV4 = uint24(vm.envOr("ARBITRUM_POOL_FEE_USDT_WBTC_V4", uint256(500)));
        int24 tickUsdtWbtcV4 = int24(int256(vm.envOr("ARBITRUM_POOL_TICK_USDT_WBTC_V4", uint256(10))));
        uint24 feeXautUsdtV4 = uint24(vm.envOr("ARBITRUM_POOL_FEE_XAUT_USDT_V4", uint256(500)));
        int24 tickXautUsdtV4 = int24(int256(vm.envOr("ARBITRUM_POOL_TICK_XAUT_USDT_V4", uint256(10))));

        configureV4PoolIfSet(swapper, usdc, usdt, feeUsdcUsdtV4, tickUsdcUsdtV4, v4Hooks, hookData, "Configured USDC/USDT V4 pool");
        configureV4PoolIfSet(swapper, usdc, wbtc, feeUsdcWbtcV4, tickUsdcWbtcV4, v4Hooks, hookData, "Configured USDC/WBTC V4 pool");
        configureV4PoolIfSet(swapper, usdt, wbtc, feeUsdtWbtcV4, tickUsdtWbtcV4, v4Hooks, hookData, "Configured USDT/WBTC V4 pool");
        configureV4PoolIfSet(swapper, xaut, usdt, feeXautUsdtV4, tickXautUsdtV4, v4Hooks, hookData, "Configured XAUT/USDT V4 pool");

        // V3 pools
        uint24 feeUsdcDaiV3 = uint24(vm.envOr("ARBITRUM_POOL_FEE_USDC_DAI_V3", uint256(100)));
        uint24 feeUsdtDaiV3 = uint24(vm.envOr("ARBITRUM_POOL_FEE_USDT_DAI_V3", uint256(100)));
        configureV3PoolIfSet(swapper, usdc, dai, feeUsdcDaiV3, "Configured USDC/DAI V3 pool");
        configureV3PoolIfSet(swapper, usdt, dai, feeUsdtDaiV3, "Configured USDT/DAI V3 pool");

        // 3. Configure explicit multi-hop routes
        // DAI <> USDC <> USDT <> XAUT
        if (dai != address(0) && usdc != address(0) && usdt != address(0) && xaut != address(0)) {
            address[] memory daiToXaut = new address[](4);
            daiToXaut[0] = dai;
            daiToXaut[1] = usdc;
            daiToXaut[2] = usdt;
            daiToXaut[3] = xaut;
            configureMultiHopPathIfSet(swapper, dai, xaut, daiToXaut, "Configured DAI -> USDC -> USDT -> XAUT");

            address[] memory xautToDai = reversePath(daiToXaut);
            configureMultiHopPathIfSet(swapper, xaut, dai, xautToDai, "Configured XAUT -> USDT -> USDC -> DAI");
        }

        // WBTC <> USDC <> USDT <> XAUT
        if (wbtc != address(0) && usdc != address(0) && usdt != address(0) && xaut != address(0)) {
            address[] memory wbtcToXaut = new address[](4);
            wbtcToXaut[0] = wbtc;
            wbtcToXaut[1] = usdc;
            wbtcToXaut[2] = usdt;
            wbtcToXaut[3] = xaut;
            configureMultiHopPathIfSet(swapper, wbtc, xaut, wbtcToXaut, "Configured WBTC -> USDC -> USDT -> XAUT");

            address[] memory xautToWbtc = reversePath(wbtcToXaut);
            configureMultiHopPathIfSet(swapper, xaut, wbtc, xautToWbtc, "Configured XAUT -> USDT -> USDC -> WBTC");
        }

        vm.stopBroadcast();
        console.log("Deployment and configuration on Arbitrum complete.");
    }
}
