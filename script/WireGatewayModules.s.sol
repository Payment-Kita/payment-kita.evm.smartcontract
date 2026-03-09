// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IGatewayModuleSetter {
    function setGatewayModules(address validator, address quote, address execution, address privacy) external;
    function setFeePolicyManager(address manager) external;
    function setAuthorizedAdapter(address adapter, bool allowed) external;
}

interface IPrivacyModuleAuth {
    function setAuthorizedGateway(address gateway, bool allowed) external;
}

interface IVaultWireAuth {
    function setAuthorizedSpender(address spender, bool authorized) external;
}

interface ISwapperWireAuth {
    function setAuthorizedCaller(address caller, bool allowed) external;
}

interface IStealthEscrowFactoryWire {
    function predictEscrow(bytes32 salt, address owner, address forwarder) external view returns (address);
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
        address vault = vm.envOr("GW_MOD_VAULT", address(0));
        address swapper = vm.envOr("GW_MOD_SWAPPER", address(0));
        address forwardExecutor = vm.envOr("GW_MOD_FORWARD_EXECUTOR", address(0));
        bool authorizeForwardExecutor = vm.envOr("GW_MOD_AUTHORIZE_FORWARD_EXECUTOR", false);
        address escrowFactory = vm.envOr("GW_MOD_ESCROW_FACTORY", address(0));

        vm.startBroadcast(pk);

        IGatewayModuleSetter(gateway).setGatewayModules(validator, quoter, executor, privacy);
        IGatewayModuleSetter(gateway).setFeePolicyManager(manager);

        if (authorizePrivacy) {
            IPrivacyModuleAuth(privacy).setAuthorizedGateway(gateway, true);
        }

        if (authorizeForwardExecutor) {
            if (forwardExecutor == address(0)) {
                forwardExecutor = privacy;
            }
            IGatewayModuleSetter(gateway).setAuthorizedAdapter(forwardExecutor, true);
            if (vault != address(0)) {
                IVaultWireAuth(vault).setAuthorizedSpender(forwardExecutor, true);
            }
            if (swapper != address(0)) {
                ISwapperWireAuth(swapper).setAuthorizedCaller(forwardExecutor, true);
            }
        }

        vm.stopBroadcast();

        console.log("WireGatewayModules complete");
        console.log("gateway:", gateway);
        console.log("validator:", validator);
        console.log("quoter:", quoter);
        console.log("executor:", executor);
        console.log("privacy:", privacy);
        console.log("feePolicyManager:", manager);
        if (authorizeForwardExecutor) {
            console.log("forwardExecutor:", forwardExecutor);
        }

        if (escrowFactory != address(0)) {
            uint256 rawSalt = vm.envOr("GW_MOD_ESCROW_SALT_UINT", uint256(0));
            bytes32 salt = rawSalt == 0 ? keccak256(abi.encodePacked("privacy-v2-wire-probe", gateway)) : bytes32(rawSalt);
            address ownerProbe = vm.envOr("GW_MOD_ESCROW_OWNER_PROBE", gateway);
            address forwarderProbe = forwardExecutor == address(0) ? privacy : forwardExecutor;
            address predicted = IStealthEscrowFactoryWire(escrowFactory).predictEscrow(salt, ownerProbe, forwarderProbe);
            console.log("escrowFactory:", escrowFactory);
            console.log("escrowProbeOwner:", ownerProbe);
            console.log("escrowProbeForwarder:", forwarderProbe);
            console.log("escrowProbePredicted:", predicted);
        }
    }
}
