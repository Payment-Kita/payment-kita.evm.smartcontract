// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PaymentKitaGateway.sol";
import "../src/gateway/modules/GatewayValidatorModule.sol";
import "../src/gateway/modules/GatewayQuoteModule.sol";
import "../src/gateway/modules/GatewayExecutionModule.sol";
import "../src/gateway/modules/GatewayPrivacyModule.sol";
import "../src/gateway/fee/FeePolicyManager.sol";
import "../src/gateway/fee/strategies/FeeStrategyDefaultV1.sol";
import "../src/privacy/StealthEscrowFactory.sol";

interface IVaultGatewayV2Patch {
    function setAuthorizedSpender(address spender, bool authorized) external;
}

interface ITokenSwapperGatewayV2Patch {
    function setAuthorizedCaller(address caller, bool allowed) external;
}

interface IOwnableGatewayV2Patch {
    function owner() external view returns (address);
}

interface IGatewayConfigSourcePatch {
    function swapper() external view returns (address);
    function enableSourceSideSwap() external view returns (bool);
    function platformFeePolicy()
        external
        view
        returns (bool enabled, uint256 perByteRate, uint256 overheadBytes, uint256 minFee, uint256 maxFee);

    function validatorModule() external view returns (address);
    function quoteModule() external view returns (address);
    function executionModule() external view returns (address);
    function privacyModule() external view returns (address);
    function feePolicyManager() external view returns (address);
}

interface IGatewayPrivacyAdminPatch {
    function setAuthorizedGateway(address gateway, bool allowed) external;
}

interface IStealthEscrowFactoryProbePatch {
    function predictEscrow(bytes32 salt, address owner, address forwarder) external view returns (address);
}

contract RedeployPaymentKitaGatewayV2PrivacyPatch is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        // Core references
        address vault = vm.envOr("REDEPLOY_V2_PATCH_VAULT", vm.envOr("REDEPLOY_V2_VAULT", address(0x67d0af7f163F45578679eDa4BDf9042E3E5FEc60)));
        address router = vm.envOr("REDEPLOY_V2_PATCH_ROUTER", vm.envOr("REDEPLOY_V2_ROUTER", address(0x1b91B56aD3aA6B35e5EAe18EE19A42574A545802)));
        address tokenRegistry = vm.envOr(
            "REDEPLOY_V2_PATCH_TOKEN_REGISTRY", vm.envOr("REDEPLOY_V2_TOKEN_REGISTRY", address(0x140fbAA1e8BE387082aeb6088E4Ffe1bf3Ba4d4f))
        );
        address feeRecipient = vm.envOr(
            "REDEPLOY_V2_PATCH_FEE_RECIPIENT",
            vm.envOr("REDEPLOY_V2_FEE_RECIPIENT", vm.envOr("FEE_RECIPIENT_ADDRESS", address(0x2Bda11F04b8F96D361D2DBB1bA8c36B744B4b42A)))
        );

        address oldGateway = vm.envOr("REDEPLOY_V2_PATCH_OLD_GATEWAY", vm.envOr("REDEPLOY_V2_OLD_GATEWAY", address(0xf0daa1a24556B68B4636FBE1c90dE326842A164C)));
        bool deauthorizeOldGateway = vm.envOr("REDEPLOY_V2_PATCH_DEAUTHORIZE_OLD_GATEWAY", false);
        bool copyConfigFromOldGateway = vm.envOr("REDEPLOY_V2_PATCH_COPY_CONFIG_FROM_OLD_GATEWAY", true);
        bool requireRuntimeWiring = vm.envOr("REDEPLOY_V2_PATCH_REQUIRE_RUNTIME_WIRING", true);

        bool deployModules = vm.envOr("REDEPLOY_V2_PATCH_DEPLOY_MODULES", true);
        bool deployFeePolicy = vm.envOr("REDEPLOY_V2_PATCH_DEPLOY_FEE_POLICY", true);
        bool deployEscrowFactory = vm.envOr("REDEPLOY_V2_PATCH_DEPLOY_ESCROW_FACTORY", true);
        bool authorizeForwardExecutor = vm.envOr("REDEPLOY_V2_PATCH_AUTHORIZE_FORWARD_EXECUTOR", false);

        // Optional explicit module/manager overrides.
        address validatorModuleAddr = vm.envOr("REDEPLOY_V2_PATCH_VALIDATOR_MODULE", vm.envOr("REDEPLOY_V2_VALIDATOR_MODULE", address(0)));
        address quoteModuleAddr = vm.envOr("REDEPLOY_V2_PATCH_QUOTE_MODULE", vm.envOr("REDEPLOY_V2_QUOTE_MODULE", address(0)));
        address executionModuleAddr = vm.envOr("REDEPLOY_V2_PATCH_EXECUTION_MODULE", vm.envOr("REDEPLOY_V2_EXECUTION_MODULE", address(0)));
        address privacyModuleAddr = vm.envOr("REDEPLOY_V2_PATCH_PRIVACY_MODULE", vm.envOr("REDEPLOY_V2_PRIVACY_MODULE", address(0)));
        address feePolicyManagerAddr =
            vm.envOr("REDEPLOY_V2_PATCH_FEE_POLICY_MANAGER", vm.envOr("REDEPLOY_V2_FEE_POLICY_MANAGER", address(0)));
        address forwardExecutor = vm.envOr("REDEPLOY_V2_PATCH_FORWARD_EXECUTOR", address(0));
        address escrowFactoryAddr = vm.envOr("REDEPLOY_V2_PATCH_ESCROW_FACTORY", address(0));

        address[8] memory adapterCandidates;
        adapterCandidates[0] = vm.envOr("REDEPLOY_V2_PATCH_ADAPTER_0", vm.envOr("REDEPLOY_V2_ADAPTER_0", address(0x46FAc7ac7D89d2daE0B647F31888AdD01cEed2bb)));
        adapterCandidates[1] = vm.envOr("REDEPLOY_V2_PATCH_ADAPTER_1", vm.envOr("REDEPLOY_V2_ADAPTER_1", address(0xc4c28aeeE5bb312970a7266461838565E1eEEc1a)));
        adapterCandidates[2] = vm.envOr("REDEPLOY_V2_PATCH_ADAPTER_2", vm.envOr("REDEPLOY_V2_ADAPTER_2", address(0x2AD1ac009fAcc6528352d5ca23fd35F025C328f3)));
        adapterCandidates[3] = vm.envOr("REDEPLOY_V2_PATCH_ADAPTER_3", vm.envOr("REDEPLOY_V2_ADAPTER_3", address(0xB9F0429D420571923EeC57E8b7025d063E361329)));
        adapterCandidates[4] = vm.envOr("REDEPLOY_V2_PATCH_ADAPTER_4", vm.envOr("REDEPLOY_V2_ADAPTER_4", address(0)));
        adapterCandidates[5] = vm.envOr("REDEPLOY_V2_PATCH_ADAPTER_5", vm.envOr("REDEPLOY_V2_ADAPTER_5", address(0)));
        adapterCandidates[6] = vm.envOr("REDEPLOY_V2_PATCH_ADAPTER_6", vm.envOr("REDEPLOY_V2_ADAPTER_6", address(0)));
        adapterCandidates[7] = vm.envOr("REDEPLOY_V2_PATCH_ADAPTER_7", vm.envOr("REDEPLOY_V2_ADAPTER_7", address(0)));

        string memory defaultRouteDest = vm.envOr("REDEPLOY_V2_PATCH_DEFAULT_DEST_CAIP2", vm.envOr("REDEPLOY_V2_DEFAULT_DEST_CAIP2", string("eip155:137")));
        uint8 defaultRouteBridgeType = uint8(vm.envOr("REDEPLOY_V2_PATCH_DEFAULT_BRIDGE_TYPE", vm.envOr("REDEPLOY_V2_DEFAULT_BRIDGE_TYPE", uint256(0))));

        if (vault == address(0) || router == address(0) || tokenRegistry == address(0) || feeRecipient == address(0)) {
            revert("RedeployV2Patch: zero core address");
        }

        address vaultOwner = IOwnableGatewayV2Patch(vault).owner();
        if (vaultOwner != deployer) {
            console.log("Signer:", deployer);
            console.log("Vault:", vault);
            console.log("Vault owner:", vaultOwner);
            revert("RedeployV2Patch: signer is not vault owner");
        }

        vm.startBroadcast(pk);

        PaymentKitaGateway gatewayV2 = new PaymentKitaGateway(vault, router, tokenRegistry, feeRecipient);
        IVaultGatewayV2Patch(vault).setAuthorizedSpender(address(gatewayV2), true);

        if (copyConfigFromOldGateway && oldGateway != address(0)) {
            _copyConfig(gatewayV2, oldGateway);
        }

        // Deploy fresh modules/managers by default unless explicit addresses are provided.
        if (deployModules) {
            if (validatorModuleAddr == address(0)) validatorModuleAddr = address(new GatewayValidatorModule());
            if (quoteModuleAddr == address(0)) quoteModuleAddr = address(new GatewayQuoteModule());
            if (executionModuleAddr == address(0)) executionModuleAddr = address(new GatewayExecutionModule());
            if (privacyModuleAddr == address(0)) privacyModuleAddr = address(new GatewayPrivacyModule());
        }

        address defaultFeeStrategy = address(0);
        if (deployFeePolicy && feePolicyManagerAddr == address(0)) {
            defaultFeeStrategy = address(new FeeStrategyDefaultV1(tokenRegistry));
            feePolicyManagerAddr = address(new FeePolicyManager(defaultFeeStrategy));
        }

        _wireRuntimeConfig(
            gatewayV2,
            oldGateway,
            validatorModuleAddr,
            quoteModuleAddr,
            executionModuleAddr,
            privacyModuleAddr,
            feePolicyManagerAddr,
            requireRuntimeWiring
        );

        _authorizePrivacyGateway(gatewayV2, requireRuntimeWiring);

        address configuredSwapper = address(gatewayV2.swapper());
        if (configuredSwapper != address(0)) {
            IVaultGatewayV2Patch(vault).setAuthorizedSpender(configuredSwapper, true);
            try ITokenSwapperGatewayV2Patch(configuredSwapper).setAuthorizedCaller(address(gatewayV2), true) {} catch {
                console.log("setAuthorizedCaller(newGateway) failed on swapper, skip");
            }
        }

        if (authorizeForwardExecutor) {
            if (forwardExecutor == address(0)) {
                forwardExecutor = gatewayV2.privacyModule();
            }
            if (forwardExecutor == address(0) && requireRuntimeWiring) {
                revert("RedeployV2Patch: forward executor missing");
            }
            if (forwardExecutor != address(0)) {
                gatewayV2.setAuthorizedAdapter(forwardExecutor, true);
                IVaultGatewayV2Patch(vault).setAuthorizedSpender(forwardExecutor, true);
                if (configuredSwapper != address(0)) {
                    try ITokenSwapperGatewayV2Patch(configuredSwapper).setAuthorizedCaller(forwardExecutor, true) {} catch {
                        console.log("setAuthorizedCaller(forwardExecutor) failed on swapper, skip");
                    }
                }
            }
        }

        for (uint256 i = 0; i < adapterCandidates.length; i++) {
            address adapter = adapterCandidates[i];
            if (adapter != address(0)) {
                gatewayV2.setAuthorizedAdapter(adapter, true);
            }
        }

        if (bytes(defaultRouteDest).length > 0) {
            gatewayV2.setDefaultBridgeType(defaultRouteDest, defaultRouteBridgeType);
        }

        if (deauthorizeOldGateway && oldGateway != address(0)) {
            IVaultGatewayV2Patch(vault).setAuthorizedSpender(oldGateway, false);
            if (configuredSwapper != address(0)) {
                try ITokenSwapperGatewayV2Patch(configuredSwapper).setAuthorizedCaller(oldGateway, false) {} catch {
                    console.log("setAuthorizedCaller(oldGateway,false) failed on swapper, skip");
                }
            }
        }

        if (escrowFactoryAddr == address(0) && deployEscrowFactory) {
            escrowFactoryAddr = address(new StealthEscrowFactory());
        }

        if (escrowFactoryAddr != address(0)) {
            _probeEscrowFactory(gatewayV2, deployer, escrowFactoryAddr, forwardExecutor);
        } else if (requireRuntimeWiring) {
            revert("RedeployV2Patch: escrow factory missing");
        }

        vm.stopBroadcast();

        console.log("RedeployPaymentKitaGatewayV2PrivacyPatch complete");
        console.log("GatewayV2:", address(gatewayV2));
        console.log("Vault:", vault);
        console.log("Router:", router);
        console.log("TokenRegistry:", tokenRegistry);
        console.log("FeeRecipient:", feeRecipient);
        console.log("RuntimeValidatorModule:", gatewayV2.validatorModule());
        console.log("RuntimeQuoteModule:", gatewayV2.quoteModule());
        console.log("RuntimeExecutionModule:", gatewayV2.executionModule());
        console.log("RuntimePrivacyModule:", gatewayV2.privacyModule());
        console.log("RuntimeFeePolicyManager:", gatewayV2.feePolicyManager());
        if (defaultFeeStrategy != address(0)) {
            console.log("DefaultFeeStrategy:", defaultFeeStrategy);
        }
        if (escrowFactoryAddr != address(0)) {
            console.log("StealthEscrowFactory:", escrowFactoryAddr);
        }
        if (bytes(defaultRouteDest).length > 0) {
            console.log("DefaultRouteDest:", defaultRouteDest);
        }
        if (oldGateway != address(0)) {
            console.log("OldGateway:", oldGateway);
            console.log("DeauthorizeOldGateway:", deauthorizeOldGateway);
            console.log("CopyConfigFromOldGateway:", copyConfigFromOldGateway);
        }
    }

    function _probeEscrowFactory(
        PaymentKitaGateway gatewayV2,
        address deployer,
        address escrowFactoryAddr,
        address forwardExecutor
    ) internal {
        uint256 rawSalt = vm.envOr("REDEPLOY_V2_PATCH_ESCROW_SALT_UINT", uint256(0));
        bytes32 salt = rawSalt == 0 ? keccak256(abi.encodePacked("privacy-v2-patch", address(gatewayV2))) : bytes32(rawSalt);
        address ownerProbe = vm.envOr("REDEPLOY_V2_PATCH_ESCROW_OWNER_PROBE", deployer);

        if (forwardExecutor == address(0)) {
            forwardExecutor = gatewayV2.privacyModule();
        }
        if (forwardExecutor == address(0)) {
            revert("RedeployV2Patch: escrow forwarder probe missing");
        }

        address predicted = IStealthEscrowFactoryProbePatch(escrowFactoryAddr).predictEscrow(salt, ownerProbe, forwardExecutor);
        address expected = vm.envOr("REDEPLOY_V2_PATCH_EXPECTED_ESCROW", address(0));
        if (expected != address(0)) {
            require(predicted == expected, "RedeployV2Patch: escrow prediction mismatch");
        }

        console.log("EscrowProbeOwner:", ownerProbe);
        console.log("EscrowProbeForwarder:", forwardExecutor);
        console.log("EscrowProbePredicted:", predicted);
    }

    function _authorizePrivacyGateway(PaymentKitaGateway gatewayV2, bool requireRuntimeWiring) internal {
        address privacy = gatewayV2.privacyModule();
        if (privacy == address(0)) {
            if (requireRuntimeWiring) {
                revert("RedeployV2Patch: privacy module missing");
            }
            return;
        }

        try IGatewayPrivacyAdminPatch(privacy).setAuthorizedGateway(address(gatewayV2), true) {
            // no-op
        } catch {
            if (requireRuntimeWiring) {
                revert("RedeployV2Patch: privacy auth failed");
            }
            console.log("Privacy module auth for gateway failed, skip");
        }
    }

    function _copyConfig(PaymentKitaGateway gatewayV2, address oldGateway) internal {
        IGatewayConfigSourcePatch old = IGatewayConfigSourcePatch(oldGateway);

        address oldSwapper = old.swapper();
        if (oldSwapper != address(0)) {
            gatewayV2.setSwapper(oldSwapper);
        }
        gatewayV2.setEnableSourceSideSwap(old.enableSourceSideSwap());

        try old.platformFeePolicy() returns (
            bool enabled, uint256 perByteRate, uint256 overheadBytes, uint256 minFee, uint256 maxFee
        ) {
            gatewayV2.setPlatformFeePolicy(enabled, perByteRate, overheadBytes, minFee, maxFee);
        } catch {
            console.log("platformFeePolicy() unavailable on old gateway, skip copy");
        }
    }

    function _wireRuntimeConfig(
        PaymentKitaGateway gatewayV2,
        address oldGateway,
        address validatorModuleAddr,
        address quoteModuleAddr,
        address executionModuleAddr,
        address privacyModuleAddr,
        address feePolicyManagerAddr,
        bool requireRuntimeWiring
    ) internal {
        if (validatorModuleAddr == address(0) && oldGateway != address(0)) {
            (, validatorModuleAddr) = _tryReadAddress(oldGateway, IGatewayConfigSourcePatch.validatorModule.selector);
        }
        if (quoteModuleAddr == address(0) && oldGateway != address(0)) {
            (, quoteModuleAddr) = _tryReadAddress(oldGateway, IGatewayConfigSourcePatch.quoteModule.selector);
        }
        if (executionModuleAddr == address(0) && oldGateway != address(0)) {
            (, executionModuleAddr) = _tryReadAddress(oldGateway, IGatewayConfigSourcePatch.executionModule.selector);
        }
        if (privacyModuleAddr == address(0) && oldGateway != address(0)) {
            (, privacyModuleAddr) = _tryReadAddress(oldGateway, IGatewayConfigSourcePatch.privacyModule.selector);
        }
        if (feePolicyManagerAddr == address(0) && oldGateway != address(0)) {
            (, feePolicyManagerAddr) = _tryReadAddress(oldGateway, IGatewayConfigSourcePatch.feePolicyManager.selector);
        }

        bool modulesReady =
            validatorModuleAddr != address(0) &&
            quoteModuleAddr != address(0) &&
            executionModuleAddr != address(0) &&
            privacyModuleAddr != address(0);

        if (modulesReady) {
            gatewayV2.setGatewayModules(validatorModuleAddr, quoteModuleAddr, executionModuleAddr, privacyModuleAddr);
        } else if (requireRuntimeWiring) {
            revert("RedeployV2Patch: missing gateway modules");
        } else {
            console.log("Gateway modules missing, skip wiring");
        }

        if (feePolicyManagerAddr != address(0)) {
            gatewayV2.setFeePolicyManager(feePolicyManagerAddr);
        } else if (requireRuntimeWiring) {
            revert("RedeployV2Patch: missing fee manager");
        } else {
            console.log("FeePolicyManager missing, skip wiring");
        }
    }

    function _tryReadAddress(address target, bytes4 selector) internal view returns (bool ok, address value) {
        (bool success, bytes memory data) = target.staticcall(abi.encodeWithSelector(selector));
        if (!success || data.length < 32) {
            return (false, address(0));
        }
        value = abi.decode(data, (address));
        return (true, value);
    }
}
