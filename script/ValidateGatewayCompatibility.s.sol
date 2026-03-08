// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IGatewayCompatibilityView {
    function owner() external view returns (address);
    function router() external view returns (address);
    function vault() external view returns (address);
    function swapper() external view returns (address);
    function tokenRegistry() external view returns (address);
    function feeRecipient() external view returns (address);
    function enableSourceSideSwap() external view returns (bool);
}

contract ValidateGatewayCompatibility is Script {
    function run() external {
        address gateway = vm.envAddress("GW_COMPAT_GATEWAY");
        address expectedRouter = vm.envOr("GW_COMPAT_ROUTER", address(0));
        address expectedVault = vm.envOr("GW_COMPAT_VAULT", address(0));
        address expectedRegistry = vm.envOr("GW_COMPAT_TOKEN_REGISTRY", address(0));
        bool strict = vm.envOr("GW_COMPAT_STRICT", true);

        IGatewayCompatibilityView gw = IGatewayCompatibilityView(gateway);

        address owner = gw.owner();
        address router = gw.router();
        address vault = gw.vault();
        address swapper = gw.swapper();
        address registry = gw.tokenRegistry();
        address feeRecipient = gw.feeRecipient();
        bool sourceSideSwap = gw.enableSourceSideSwap();

        console.log("Gateway compatibility snapshot");
        console.log("gateway:", gateway);
        console.log("owner:", owner);
        console.log("router:", router);
        console.log("vault:", vault);
        console.log("swapper:", swapper);
        console.log("tokenRegistry:", registry);
        console.log("feeRecipient:", feeRecipient);
        console.log("enableSourceSideSwap:", sourceSideSwap);

        if (strict) {
            require(owner != address(0), "owner is zero");
            require(router != address(0), "router is zero");
            require(vault != address(0), "vault is zero");
            require(registry != address(0), "registry is zero");
            require(feeRecipient != address(0), "feeRecipient is zero");
        }
        if (expectedRouter != address(0)) {
            require(router == expectedRouter, "router mismatch");
        }
        if (expectedVault != address(0)) {
            require(vault == expectedVault, "vault mismatch");
        }
        if (expectedRegistry != address(0)) {
            require(registry == expectedRegistry, "tokenRegistry mismatch");
        }
    }
}

