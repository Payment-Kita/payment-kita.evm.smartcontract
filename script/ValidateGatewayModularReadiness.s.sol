// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IGatewayModularView {
    function validatorModule() external view returns (address);
    function quoteModule() external view returns (address);
    function executionModule() external view returns (address);
    function privacyModule() external view returns (address);
    function feePolicyManager() external view returns (address);
}

interface IFeeManagerReadinessView {
    function defaultStrategy() external view returns (address);
    function activeStrategy() external view returns (address);
    function resolveStrategy() external view returns (address);
}

contract ValidateGatewayModularReadiness is Script {
    function run() external {
        address gateway = vm.envAddress("GW_MOD_GATEWAY");
        bool strict = vm.envOr("GW_MOD_VALIDATE_STRICT", true);

        IGatewayModularView gw = IGatewayModularView(gateway);
        address validator = gw.validatorModule();
        address quoter = gw.quoteModule();
        address executor = gw.executionModule();
        address privacy = gw.privacyModule();
        address manager = gw.feePolicyManager();

        console.log("Gateway modular readiness");
        console.log("gateway:", gateway);
        console.log("validator:", validator);
        console.log("quoter:", quoter);
        console.log("executor:", executor);
        console.log("privacy:", privacy);
        console.log("feePolicyManager:", manager);

        if (strict) {
            require(validator != address(0), "validator module not set");
            require(quoter != address(0), "quote module not set");
            require(executor != address(0), "execution module not set");
            require(privacy != address(0), "privacy module not set");
            require(manager != address(0), "fee policy manager not set");
        }

        if (manager != address(0)) {
            address defaultStrategy = IFeeManagerReadinessView(manager).defaultStrategy();
            address activeStrategy = IFeeManagerReadinessView(manager).activeStrategy();
            address resolved = IFeeManagerReadinessView(manager).resolveStrategy();
            console.log("defaultStrategy:", defaultStrategy);
            console.log("activeStrategy:", activeStrategy);
            console.log("resolvedStrategy:", resolved);
            if (strict) {
                require(defaultStrategy != address(0), "default strategy not set");
                require(resolved != address(0), "resolved strategy not set");
            }
        }
    }
}

