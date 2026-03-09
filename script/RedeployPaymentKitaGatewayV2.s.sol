// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PaymentKitaGateway.sol";

interface IVaultGatewayV2 {
    function setAuthorizedSpender(address spender, bool authorized) external;
}

interface ITokenSwapperGatewayV2 {
    function setAuthorizedCaller(address caller, bool allowed) external;
}

interface IOwnableGatewayV2 {
    function owner() external view returns (address);
}

interface IGatewayConfigSource {
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

interface IGatewayPrivacyAdmin {
    function setAuthorizedGateway(address gateway, bool allowed) external;
}

contract RedeployPaymentKitaGatewayV2 is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        // ----------------------------
        // Base mainnet defaults (can be overridden by env)
        // Source of truth default: CHAIN_BASE.md
        // ----------------------------
        address vault = vm.envOr("REDEPLOY_V2_VAULT", address(0x67d0af7f163F45578679eDa4BDf9042E3E5FEc60));
        address router = vm.envOr("REDEPLOY_V2_ROUTER", address(0x1b91B56aD3aA6B35e5EAe18EE19A42574A545802));
        address tokenRegistry = vm.envOr("REDEPLOY_V2_TOKEN_REGISTRY", address(0x140fbAA1e8BE387082aeb6088E4Ffe1bf3Ba4d4f));
        address feeRecipient = vm.envOr(
            "REDEPLOY_V2_FEE_RECIPIENT", vm.envOr("FEE_RECIPIENT_ADDRESS", address(0x2Bda11F04b8F96D361D2DBB1bA8c36B744B4b42A))
        );

        address oldGateway = vm.envOr("REDEPLOY_V2_OLD_GATEWAY", address(0xf0daa1a24556B68B4636FBE1c90dE326842A164C));
        bool deauthorizeOldGateway = vm.envOr("REDEPLOY_V2_DEAUTHORIZE_OLD_GATEWAY", false);
        bool copyConfigFromOldGateway = vm.envOr("REDEPLOY_V2_COPY_CONFIG_FROM_OLD_GATEWAY", true);
        bool requireRuntimeWiring = vm.envOr("REDEPLOY_V2_REQUIRE_RUNTIME_WIRING", true);

        // Optional explicit module/manager overrides.
        address explicitValidatorModule = vm.envOr("REDEPLOY_V2_VALIDATOR_MODULE", address(0));
        address explicitQuoteModule = vm.envOr("REDEPLOY_V2_QUOTE_MODULE", address(0));
        address explicitExecutionModule = vm.envOr("REDEPLOY_V2_EXECUTION_MODULE", address(0));
        address explicitPrivacyModule = vm.envOr("REDEPLOY_V2_PRIVACY_MODULE", address(0));
        address explicitFeePolicyManager = vm.envOr("REDEPLOY_V2_FEE_POLICY_MANAGER", address(0));

        address[8] memory adapterCandidates;
        // Active defaults from CHAIN_BASE.md
        adapterCandidates[0] = vm.envOr("REDEPLOY_V2_ADAPTER_0", address(0x46FAc7ac7D89d2daE0B647F31888AdD01cEed2bb)); // CCIPReceiverAdapter
        adapterCandidates[1] = vm.envOr("REDEPLOY_V2_ADAPTER_1", address(0xc4c28aeeE5bb312970a7266461838565E1eEEc1a)); // LayerZeroReceiverAdapter
        adapterCandidates[2] = vm.envOr("REDEPLOY_V2_ADAPTER_2", address(0x2AD1ac009fAcc6528352d5ca23fd35F025C328f3)); // HyperbridgeReceiver
        adapterCandidates[3] = vm.envOr("REDEPLOY_V2_ADAPTER_3", address(0xB9F0429D420571923EeC57E8b7025d063E361329)); // HyperbridgeSender
        adapterCandidates[4] = vm.envOr("REDEPLOY_V2_ADAPTER_4", address(0));
        adapterCandidates[5] = vm.envOr("REDEPLOY_V2_ADAPTER_5", address(0));
        adapterCandidates[6] = vm.envOr("REDEPLOY_V2_ADAPTER_6", address(0));
        adapterCandidates[7] = vm.envOr("REDEPLOY_V2_ADAPTER_7", address(0));

        uint256 adapterCount;
        for (uint256 i = 0; i < adapterCandidates.length; i++) {
            if (adapterCandidates[i] != address(0)) {
                adapterCount++;
            }
        }
        address[] memory adapters = new address[](adapterCount);
        uint256 adapterWriteIdx;
        for (uint256 i = 0; i < adapterCandidates.length; i++) {
            if (adapterCandidates[i] != address(0)) {
                adapters[adapterWriteIdx] = adapterCandidates[i];
                adapterWriteIdx++;
            }
        }

        string memory defaultRouteDest = vm.envOr("REDEPLOY_V2_DEFAULT_DEST_CAIP2", string("eip155:137"));
        uint8 defaultRouteBridgeType = uint8(vm.envOr("REDEPLOY_V2_DEFAULT_BRIDGE_TYPE", uint256(0)));

        if (vault == address(0) || router == address(0) || tokenRegistry == address(0) || feeRecipient == address(0)) {
            revert("RedeployV2: zero core address");
        }

        // Preflight guard: avoid broadcasting when signer cannot configure vault.
        address vaultOwner = IOwnableGatewayV2(vault).owner();
        if (vaultOwner != deployer) {
            console.log("Signer:", deployer);
            console.log("Vault:", vault);
            console.log("Vault owner:", vaultOwner);
            revert("RedeployV2: signer is not vault owner");
        }

        vm.startBroadcast(pk);

        PaymentKitaGateway gatewayV2 = new PaymentKitaGateway(vault, router, tokenRegistry, feeRecipient);

        // Authorize new gateway in vault so it can pull/push user funds.
        IVaultGatewayV2(vault).setAuthorizedSpender(address(gatewayV2), true);

        // Optional: copy selected runtime config from old gateway.
        if (copyConfigFromOldGateway && oldGateway != address(0)) {
            _copyConfig(gatewayV2, oldGateway);
        }

        _wireRuntimeConfig(
            gatewayV2,
            oldGateway,
            explicitValidatorModule,
            explicitQuoteModule,
            explicitExecutionModule,
            explicitPrivacyModule,
            explicitFeePolicyManager,
            requireRuntimeWiring
        );

        _authorizePrivacyGateway(gatewayV2, requireRuntimeWiring);

        // Re-wire swapper auth for new gateway (if swapper already configured/copied).
        address configuredSwapper = address(gatewayV2.swapper());
        if (configuredSwapper != address(0)) {
            // Ensure vault still allows swapper pull/push flows.
            IVaultGatewayV2(vault).setAuthorizedSpender(configuredSwapper, true);
            // Ensure swapper allows calls from new gateway.
            try ITokenSwapperGatewayV2(configuredSwapper).setAuthorizedCaller(address(gatewayV2), true) {
                // no-op
            } catch {
                console.log("setAuthorizedCaller(newGateway) failed on swapper, skip");
            }
        }

        // Authorize existing adapters in new gateway for markPaymentFailed/finalization callback paths.
        for (uint256 i = 0; i < adapters.length; i++) {
            address adapter = adapters[i];
            gatewayV2.setAuthorizedAdapter(adapter, true);
        }

        // Optional: set default bridge type for known route.
        if (bytes(defaultRouteDest).length > 0) {
            gatewayV2.setDefaultBridgeType(defaultRouteDest, defaultRouteBridgeType);
        }

        if (deauthorizeOldGateway && oldGateway != address(0)) {
            IVaultGatewayV2(vault).setAuthorizedSpender(oldGateway, false);
            if (configuredSwapper != address(0)) {
                try ITokenSwapperGatewayV2(configuredSwapper).setAuthorizedCaller(oldGateway, false) {
                    // no-op
                } catch {
                    console.log("setAuthorizedCaller(oldGateway,false) failed on swapper, skip");
                }
            }
        }

        vm.stopBroadcast();

        console.log("RedeployPaymentKitaGatewayV2 complete");
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
        if (bytes(defaultRouteDest).length > 0) {
            console.log("DefaultRouteDest:", defaultRouteDest);
        }
        if (oldGateway != address(0)) {
            console.log("OldGateway:", oldGateway);
            console.log("DeauthorizeOldGateway:", deauthorizeOldGateway);
            console.log("CopyConfigFromOldGateway:", copyConfigFromOldGateway);
        }
    }

    function _authorizePrivacyGateway(PaymentKitaGateway gatewayV2, bool requireRuntimeWiring) internal {
        address privacy = gatewayV2.privacyModule();
        if (privacy == address(0)) {
            if (requireRuntimeWiring) {
                revert("RedeployV2: privacy module missing");
            }
            return;
        }

        try IGatewayPrivacyAdmin(privacy).setAuthorizedGateway(address(gatewayV2), true) {
            // no-op
        } catch {
            if (requireRuntimeWiring) {
                revert("RedeployV2: privacy auth failed");
            }
            console.log("Privacy module auth for gateway failed, skip");
        }
    }

    function _copyConfig(PaymentKitaGateway gatewayV2, address oldGateway) internal {
        IGatewayConfigSource old = IGatewayConfigSource(oldGateway);

        address oldSwapper = old.swapper();
        if (oldSwapper != address(0)) {
            gatewayV2.setSwapper(oldSwapper);
        }
        gatewayV2.setEnableSourceSideSwap(old.enableSourceSideSwap());

        // Optional (Track-B): not all legacy gateways expose platformFeePolicy().
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
            (, validatorModuleAddr) = _tryReadAddress(oldGateway, IGatewayConfigSource.validatorModule.selector);
        }
        if (quoteModuleAddr == address(0) && oldGateway != address(0)) {
            (, quoteModuleAddr) = _tryReadAddress(oldGateway, IGatewayConfigSource.quoteModule.selector);
        }
        if (executionModuleAddr == address(0) && oldGateway != address(0)) {
            (, executionModuleAddr) = _tryReadAddress(oldGateway, IGatewayConfigSource.executionModule.selector);
        }
        if (privacyModuleAddr == address(0) && oldGateway != address(0)) {
            (, privacyModuleAddr) = _tryReadAddress(oldGateway, IGatewayConfigSource.privacyModule.selector);
        }
        if (feePolicyManagerAddr == address(0) && oldGateway != address(0)) {
            (, feePolicyManagerAddr) = _tryReadAddress(oldGateway, IGatewayConfigSource.feePolicyManager.selector);
        }

        bool modulesReady =
            validatorModuleAddr != address(0) &&
            quoteModuleAddr != address(0) &&
            executionModuleAddr != address(0) &&
            privacyModuleAddr != address(0);

        if (modulesReady) {
            gatewayV2.setGatewayModules(validatorModuleAddr, quoteModuleAddr, executionModuleAddr, privacyModuleAddr);
        } else if (requireRuntimeWiring) {
            revert("RedeployV2: missing gateway modules");
        } else {
            console.log("Gateway modules missing, skip wiring");
        }

        if (feePolicyManagerAddr != address(0)) {
            gatewayV2.setFeePolicyManager(feePolicyManagerAddr);
        } else if (requireRuntimeWiring) {
            revert("RedeployV2: missing fee manager");
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
