// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./DeployCommon.s.sol";

contract DeployPolygon is DeployCommon {
    function run() public {
        address feeRecipient = vm.envAddress("FEE_RECIPIENT_ADDRESS");

        DeploymentConfig memory config = DeploymentConfig({
            ccipRouter: vm.envOr("POLYGON_CCIP_ROUTER", address(0)),
            hyperbridgeHost: vm.envOr("POLYGON_HYPERBRIDGE_HOST", address(0)),
            layerZeroEndpointV2: vm.envOr("POLYGON_LAYERZERO_ENDPOINT_V2", address(0)),
            uniswapUniversalRouter: vm.envOr("POLYGON_UNIVERSAL_ROUTER", address(0)),
            uniswapPoolManager: vm.envOr("POLYGON_POOL_MANAGER", address(0)),
            bridgeToken: vm.envOr("POLYGON_USDC", address(0)),
            feeRecipient: feeRecipient,
            enableSourceSideSwap: vm.envOr("POLYGON_ENABLE_SOURCE_SIDE_SWAP", vm.envOr("ENABLE_SOURCE_SIDE_SWAP", false))
        });

        console.log("Deploying to Polygon...");
        (PaymentKitaGateway gateway, , TokenRegistry registry, TokenSwapper swapper) = deploySystem(config);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        bool strict = strictTokenRegistration();
        address v3Router = vm.envOr("POLYGON_V3_ROUTER", address(0));
        require(v3Router != address(0), "DEPLOYMENT ERROR: POLYGON_V3_ROUTER must be set");
        swapper.setV3Router(v3Router);
        require(swapper.swapRouterV3() == v3Router, "DEPLOYMENT ERROR: POLYGON V3 router mismatch");
        console.log("Configured V3 router:", v3Router);
        require(gateway.privacyModule() != address(0), "DEPLOYMENT ERROR: privacy module missing");
        require(GatewayPrivacyModule(gateway.privacyModule()).authorizedGateway(address(gateway)), "DEPLOYMENT ERROR: privacy auth missing");
        require(swapper.authorizedCallers(address(gateway)), "DEPLOYMENT ERROR: swapper gateway auth missing");
        require(registry.isTokenSupported(config.bridgeToken), "DEPLOYMENT ERROR: bridge token unsupported");

        // 1. Register tokens + decimals
        address usdc = config.bridgeToken;
        address idrt = vm.envOr("POLYGON_IDRT", address(0));
        address usdt = vm.envOr("POLYGON_USDT", address(0));
        address weth = vm.envOr("POLYGON_WETH", address(0));
        address dai = vm.envOr("POLYGON_DAI", address(0));

        uint256 usdcDec = vm.envOr("POLYGON_USDC_DECIMAL", uint256(0));
        uint256 idrtDec = vm.envOr("POLYGON_IDRT_DECIMAL", uint256(0));
        uint256 usdtDec = vm.envOr("POLYGON_USDT_DECIMAL", uint256(0));
        uint256 wethDec = vm.envOr("POLYGON_WETH_DECIMAL", uint256(0));
        uint256 daiDec = vm.envOr("POLYGON_DAI_DECIMAL", uint256(0));

        registerTokenWithOptionalDecimals(registry, usdc, usdcDec, true, "POLYGON_USDC", "POLYGON_USDC_DECIMAL");
        registerTokenWithOptionalDecimals(registry, idrt, idrtDec, strict, "POLYGON_IDRT", "POLYGON_IDRT_DECIMAL");
        registerTokenWithOptionalDecimals(registry, usdt, usdtDec, strict, "POLYGON_USDT", "POLYGON_USDT_DECIMAL");
        registerTokenWithOptionalDecimals(registry, weth, wethDec, strict, "POLYGON_WETH", "POLYGON_WETH_DECIMAL");
        registerTokenWithOptionalDecimals(registry, dai, daiDec, strict, "POLYGON_DAI", "POLYGON_DAI_DECIMAL");

        // 2. Configure V3 Pools on Swapper
        // Direct pools are stored by unordered pair key, so a single set covers A<->B.
        uint24 feeUsdtIdrt = uint24(vm.envOr("POLYGON_POOL_FEE_USDT_IDRT", uint256(10000)));
        uint24 feeUsdcUsdt = uint24(vm.envOr("POLYGON_POOL_FEE_USDC_USDT", uint256(100)));
        uint24 feeUsdcWeth = uint24(vm.envOr("POLYGON_POOL_FEE_USDC_WETH", uint256(500)));
        uint24 feeUsdtWeth = uint24(vm.envOr("POLYGON_POOL_FEE_USDT_WETH", uint256(500)));
        uint24 feeUsdtDai = uint24(vm.envOr("POLYGON_POOL_FEE_USDT_DAI", uint256(100)));
        uint24 feeUsdcDai = uint24(vm.envOr("POLYGON_POOL_FEE_USDC_DAI", uint256(100)));

        configureV3PoolIfSet(swapper, usdt, idrt, feeUsdtIdrt, "Configured USDT/IDRT V3 pool");
        configureV3PoolIfSet(swapper, usdc, usdt, feeUsdcUsdt, "Configured USDC/USDT V3 pool");
        configureV3PoolIfSet(swapper, usdc, weth, feeUsdcWeth, "Configured USDC/WETH V3 pool");
        configureV3PoolIfSet(swapper, usdt, weth, feeUsdtWeth, "Configured USDT/WETH V3 pool");
        configureV3PoolIfSet(swapper, usdt, dai, feeUsdtDai, "Configured USDT/DAI V3 pool");
        configureV3PoolIfSet(swapper, usdc, dai, feeUsdcDai, "Configured USDC/DAI V3 pool");

        // 3. Configure explicit multi-hop routes (directional)
        // 7) USDC <-> USDT <-> IDRT
        if (usdc != address(0) && usdt != address(0) && idrt != address(0)) {
            address[] memory usdcToIdrt = new address[](3);
            usdcToIdrt[0] = usdc;
            usdcToIdrt[1] = usdt;
            usdcToIdrt[2] = idrt;
            configureMultiHopPathIfSet(swapper, usdc, idrt, usdcToIdrt, "Configured USDC -> USDT -> IDRT");

            address[] memory idrtToUsdc = reversePath(usdcToIdrt);
            configureMultiHopPathIfSet(swapper, idrt, usdc, idrtToUsdc, "Configured IDRT -> USDT -> USDC");
        }

        // 8) DAI <-> USDC <-> WETH
        if (dai != address(0) && usdc != address(0) && weth != address(0)) {
            address[] memory daiToWeth = new address[](3);
            daiToWeth[0] = dai;
            daiToWeth[1] = usdc;
            daiToWeth[2] = weth;
            configureMultiHopPathIfSet(swapper, dai, weth, daiToWeth, "Configured DAI -> USDC -> WETH");

            address[] memory wethToDai = reversePath(daiToWeth);
            configureMultiHopPathIfSet(swapper, weth, dai, wethToDai, "Configured WETH -> USDC -> DAI");
        }

        vm.stopBroadcast();
        console.log("Deployment and configuration on Polygon complete.");
    }
}
