// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IFeeGatewaySetter {
    function setFeePolicyManager(address manager) external;
}

interface IFeePolicyManagerSetter {
    function setDefaultStrategy(address strategy) external;
    function setActiveStrategy(address strategy) external;
    function clearActiveStrategy() external;
}

contract SetGatewayFeeStrategy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        string memory mode = vm.envOr("GW_FEE_STRATEGY_MODE", string("set-manager"));
        address gateway = vm.envOr("GW_FEE_GATEWAY", address(0));
        address manager = vm.envOr("GW_FEE_POLICY_MANAGER", address(0));
        address strategy = vm.envOr("GW_FEE_STRATEGY_ADDRESS", address(0));

        vm.startBroadcast(pk);

        if (_eq(mode, "set-manager")) {
            require(gateway != address(0), "Missing GW_FEE_GATEWAY");
            require(manager != address(0), "Missing GW_FEE_POLICY_MANAGER");
            IFeeGatewaySetter(gateway).setFeePolicyManager(manager);
            console.log("setFeePolicyManager gateway:", gateway);
            console.log("manager:", manager);
        } else if (_eq(mode, "set-default")) {
            require(manager != address(0), "Missing GW_FEE_POLICY_MANAGER");
            require(strategy != address(0), "Missing GW_FEE_STRATEGY_ADDRESS");
            IFeePolicyManagerSetter(manager).setDefaultStrategy(strategy);
            console.log("setDefaultStrategy manager:", manager);
            console.log("strategy:", strategy);
        } else if (_eq(mode, "set-active")) {
            require(manager != address(0), "Missing GW_FEE_POLICY_MANAGER");
            require(strategy != address(0), "Missing GW_FEE_STRATEGY_ADDRESS");
            IFeePolicyManagerSetter(manager).setActiveStrategy(strategy);
            console.log("setActiveStrategy manager:", manager);
            console.log("strategy:", strategy);
        } else if (_eq(mode, "clear-active")) {
            require(manager != address(0), "Missing GW_FEE_POLICY_MANAGER");
            IFeePolicyManagerSetter(manager).clearActiveStrategy();
            console.log("clearActiveStrategy manager:", manager);
        } else {
            revert("Unsupported GW_FEE_STRATEGY_MODE");
        }

        vm.stopBroadcast();
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}

