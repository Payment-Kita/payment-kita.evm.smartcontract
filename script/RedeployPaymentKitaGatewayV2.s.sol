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
        if (bytes(defaultRouteDest).length > 0) {
            console.log("DefaultRouteDest:", defaultRouteDest);
        }
        if (oldGateway != address(0)) {
            console.log("OldGateway:", oldGateway);
            console.log("DeauthorizeOldGateway:", deauthorizeOldGateway);
            console.log("CopyConfigFromOldGateway:", copyConfigFromOldGateway);
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
}
