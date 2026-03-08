// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IFeeGatewayView {
    function feePolicyManager() external view returns (address);
}

interface IFeePolicyManagerView {
    function defaultStrategy() external view returns (address);
    function activeStrategy() external view returns (address);
    function resolveStrategy() external view returns (address);
}

contract ValidateFeeStrategy is Script {
    function run() external {
        address gateway = vm.envAddress("GW_FEE_GATEWAY");
        address expectedManager = vm.envOr("GW_FEE_POLICY_MANAGER", address(0));
        address expectedResolved = vm.envOr("GW_FEE_EXPECTED_RESOLVED_STRATEGY", address(0));

        address manager = IFeeGatewayView(gateway).feePolicyManager();
        console.log("gateway:", gateway);
        console.log("feePolicyManager:", manager);

        if (expectedManager != address(0)) {
            require(manager == expectedManager, "Fee manager mismatch");
        }

        if (manager == address(0)) {
            console.log("No manager configured on gateway");
            return;
        }

        address defaultStrategy = IFeePolicyManagerView(manager).defaultStrategy();
        address activeStrategy = IFeePolicyManagerView(manager).activeStrategy();
        address resolvedStrategy = IFeePolicyManagerView(manager).resolveStrategy();

        console.log("defaultStrategy:", defaultStrategy);
        console.log("activeStrategy:", activeStrategy);
        console.log("resolvedStrategy:", resolvedStrategy);

        require(resolvedStrategy != address(0), "Resolved strategy is zero");
        if (expectedResolved != address(0)) {
            require(resolvedStrategy == expectedResolved, "Resolved strategy mismatch");
        }
    }
}
