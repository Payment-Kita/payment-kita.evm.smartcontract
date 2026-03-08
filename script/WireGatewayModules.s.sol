// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IGatewayModuleSetter {
    function setGatewayModules(address validator, address quote, address execution, address privacy) external;
    function setFeePolicyManager(address manager) external;
}

interface IPrivacyModuleAuth {
    function setAuthorizedGateway(address gateway, bool allowed) external;
}

contract WireGatewayModules is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address gateway = vm.envAddress("GW_MOD_GATEWAY");
        address validator = vm.envAddress("GW_MOD_VALIDATOR_MODULE");
        address quoter = vm.envAddress("GW_MOD_QUOTE_MODULE");
        address executor = vm.envAddress("GW_MOD_EXECUTION_MODULE");
        address privacy = vm.envAddress("GW_MOD_PRIVACY_MODULE");
        address manager = vm.envAddress("GW_MOD_FEE_POLICY_MANAGER");
        bool authorizePrivacy = vm.envOr("GW_MOD_AUTHORIZE_PRIVACY_GATEWAY", true);

        vm.startBroadcast(pk);

        IGatewayModuleSetter(gateway).setGatewayModules(validator, quoter, executor, privacy);
        IGatewayModuleSetter(gateway).setFeePolicyManager(manager);

        if (authorizePrivacy) {
            IPrivacyModuleAuth(privacy).setAuthorizedGateway(gateway, true);
        }

        vm.stopBroadcast();

        console.log("WireGatewayModules complete");
        console.log("gateway:", gateway);
        console.log("validator:", validator);
        console.log("quoter:", quoter);
        console.log("executor:", executor);
        console.log("privacy:", privacy);
        console.log("feePolicyManager:", manager);
    }
}

