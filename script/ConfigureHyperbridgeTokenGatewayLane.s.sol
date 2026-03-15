// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/integrations/hyperbridge/HyperbridgeTokenGatewaySender.sol";
import "../src/integrations/hyperbridge/HyperbridgeTokenReceiverAdapter.sol";

interface IHBTokenLaneGateway {
    function router() external view returns (address);
    function tokenRegistry() external view returns (address);
    function vault() external view returns (address);
    function swapper() external view returns (address);
    function defaultBridgeTypes(string calldata destChainId) external view returns (uint8);
    function bridgeTokenByDestCaip2(string calldata destChainId) external view returns (address);
    function setAuthorizedAdapter(address adapter, bool authorized) external;
    function setBridgeTokenForDest(string calldata destChainId, address bridgeTokenSource) external;
    function setDefaultBridgeType(string calldata destChainId, uint8 bridgeType) external;
}

interface IHBTokenLaneRouter {
    function adapters(string calldata destChainId, uint8 bridgeType) external view returns (address);
    function registerAdapter(string calldata destChainId, uint8 bridgeType, address adapter) external;
    function setBridgeMode(uint8 bridgeType, uint8 mode) external;
    function setTokenBridgeDestSwapCapability(uint8 bridgeType, bool enabled) external;
    function setTokenBridgePrivacySettlementCapability(uint8 bridgeType, bool enabled) external;
    function isRouteConfigured(string calldata destChainId, uint8 bridgeType) external view returns (bool);
}

interface IHBTokenLaneRegistry {
    function isTokenSupported(address token) external view returns (bool);
    function setTokenSupport(address token, bool supported) external;
    function setTokenDecimals(address token, uint8 decimals) external;
}

interface IHBTokenLaneVault {
    function setAuthorizedSpender(address spender, bool authorized) external;
}

interface IHBTokenLaneSwapper {
    function setAuthorizedCaller(address caller, bool allowed) external;
}

contract ConfigureHyperbridgeTokenGatewayLane is Script {
    uint8 internal constant TOKEN_BRIDGE_MODE = 1;

    error MissingGateway();
    error MissingTokenGateway();
    error MissingBridgeToken();
    error MissingDestCaip2();
    error MissingSettlementExecutor();
    error MissingAssetId();
    error InvalidDerivedStateMachine(string destCaip2);
    error InvalidCoreAddress(string name);
    error WiringNotReady(string reason);

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        address gatewayAddr = vm.envAddress("HB_TOKEN_GATEWAY_CONTRACT");
        if (gatewayAddr == address(0)) revert MissingGateway();

        address tokenGatewayAddr = vm.envAddress("HB_TOKEN_TOKEN_GATEWAY");
        if (tokenGatewayAddr == address(0)) revert MissingTokenGateway();

        address bridgeToken = vm.envAddress("HB_TOKEN_BRIDGE_TOKEN");
        if (bridgeToken == address(0)) revert MissingBridgeToken();

        bool deployOnly = vm.envOr("HB_TOKEN_DEPLOY_ONLY", false);
        string memory destCaip2 = vm.envString("HB_TOKEN_DEST_CAIP2");
        if (bytes(destCaip2).length == 0) revert MissingDestCaip2();

        address settlementExecutor = vm.envOr("HB_TOKEN_SETTLEMENT_EXECUTOR", address(0));
        if (!deployOnly && settlementExecutor == address(0)) revert MissingSettlementExecutor();

        bytes32 assetId = vm.envOr("HB_TOKEN_ASSET_ID", bytes32(0));
        if (assetId == bytes32(0)) {
            string memory symbol = vm.envOr("HB_TOKEN_ASSET_SYMBOL", string(""));
            if (bytes(symbol).length == 0) revert MissingAssetId();
            assetId = keccak256(bytes(symbol));
        }

        bytes memory stateMachineId = bytes("");
        if (!deployOnly) {
            string memory stateMachineText = vm.envOr("HB_TOKEN_STATE_MACHINE_ID", string(""));
            stateMachineId = bytes(stateMachineText);
            if (stateMachineId.length == 0) {
                stateMachineId = _deriveStateMachineId(destCaip2);
                if (stateMachineId.length == 0) revert InvalidDerivedStateMachine(destCaip2);
            }
        }

        uint8 bridgeType = uint8(vm.envOr("HB_TOKEN_BRIDGE_TYPE", uint256(3)));
        uint256 nativeCost = vm.envOr("HB_TOKEN_NATIVE_COST", uint256(0));
        uint256 relayerFee = vm.envOr("HB_TOKEN_RELAYER_FEE", uint256(0));
        uint64 routeTimeout = uint64(vm.envOr("HB_TOKEN_ROUTE_TIMEOUT", uint256(0)));
        bool enableDestSwap = vm.envOr("HB_TOKEN_ENABLE_DEST_SWAP", true);
        bool enablePrivacySettlement = vm.envOr("HB_TOKEN_ENABLE_PRIVACY_SETTLEMENT", true);

        address senderAddr = vm.envOr("HB_TOKEN_SENDER", address(0));
        address receiverAddr = vm.envOr("HB_TOKEN_RECEIVER", address(0));

        IHBTokenLaneGateway gateway = IHBTokenLaneGateway(gatewayAddr);
        address routerAddr = gateway.router();
        address registryAddr = gateway.tokenRegistry();
        address vaultAddr = gateway.vault();
        address swapperAddr = gateway.swapper();

        if (routerAddr == address(0)) revert InvalidCoreAddress("router");
        if (registryAddr == address(0)) revert InvalidCoreAddress("tokenRegistry");
        if (vaultAddr == address(0)) revert InvalidCoreAddress("vault");
        if (swapperAddr == address(0)) revert InvalidCoreAddress("swapper");

        vm.startBroadcast(pk);

        if (senderAddr == address(0)) {
            senderAddr = address(new HyperbridgeTokenGatewaySender(vaultAddr, tokenGatewayAddr, gatewayAddr, routerAddr));
        }
        if (receiverAddr == address(0)) {
            receiverAddr = address(new HyperbridgeTokenReceiverAdapter(tokenGatewayAddr, gatewayAddr, vaultAddr));
        }

        HyperbridgeTokenGatewaySender(senderAddr).setTokenAssetId(bridgeToken, assetId);
        HyperbridgeTokenReceiverAdapter(receiverAddr).setSwapper(swapperAddr);

        if (!deployOnly) {
            IHBTokenLaneVault(vaultAddr).setAuthorizedSpender(senderAddr, true);
            IHBTokenLaneVault(vaultAddr).setAuthorizedSpender(receiverAddr, true);
            gateway.setAuthorizedAdapter(receiverAddr, true);
            IHBTokenLaneSwapper(swapperAddr).setAuthorizedCaller(receiverAddr, true);

            IHBTokenLaneRegistry(registryAddr).setTokenSupport(bridgeToken, true);
            uint256 tokenDecimals = vm.envOr("HB_TOKEN_BRIDGE_TOKEN_DECIMALS", uint256(0));
            if (tokenDecimals > 0) {
                if (tokenDecimals > type(uint8).max) revert WiringNotReady("bridge token decimals overflow");
                // forge-lint: disable-next-line(unsafe-typecast)
                IHBTokenLaneRegistry(registryAddr).setTokenDecimals(bridgeToken, uint8(tokenDecimals));
            }

            HyperbridgeTokenGatewaySender(senderAddr).setStateMachineId(destCaip2, stateMachineId);
            HyperbridgeTokenGatewaySender(senderAddr).setRouteSettlementExecutor(destCaip2, settlementExecutor);
            HyperbridgeTokenGatewaySender(senderAddr).setNativeCost(destCaip2, nativeCost);
            HyperbridgeTokenGatewaySender(senderAddr).setRelayerFee(destCaip2, relayerFee);
            if (routeTimeout > 0) {
                HyperbridgeTokenGatewaySender(senderAddr).setRouteTimeout(destCaip2, routeTimeout);
            }

            IHBTokenLaneRouter router = IHBTokenLaneRouter(routerAddr);
            router.registerAdapter(destCaip2, bridgeType, senderAddr);
            router.setBridgeMode(bridgeType, TOKEN_BRIDGE_MODE);
            // NOTE:
            // Some deployed routers do not expose token-bridge capability setters/getters.
            // On broadcast scripts, even intentionally ignored reverts can still fail the run.
            // Keep lane wiring deterministic by skipping capability setter transactions here.
            // Route-readiness gate already handles legacy routers via optional capability checks.
            console.log("Capability setter skipped:", "destSwap");
            console.log("Capability setter skipped:", "privacySettlement");

            gateway.setBridgeTokenForDest(destCaip2, bridgeToken);
            gateway.setDefaultBridgeType(destCaip2, bridgeType);
        }

        vm.stopBroadcast();

        if (!deployOnly) {
            IHBTokenLaneRouter router = IHBTokenLaneRouter(routerAddr);
            _postCheck(gateway, router, senderAddr, destCaip2, bridgeType, bridgeToken, assetId);
        }

        console.log("ConfigureHyperbridgeTokenGatewayLane complete.");
        console.log("Deploy only:", deployOnly);
        console.log("Gateway:", gatewayAddr);
        console.log("Dest CAIP2:", destCaip2);
        console.log("Bridge type:", bridgeType);
        console.log("TokenGateway:", tokenGatewayAddr);
        console.log("Bridge token:", bridgeToken);
        console.logBytes32(assetId);
        console.log("Sender:", senderAddr);
        console.log("Receiver:", receiverAddr);
        if (settlementExecutor != address(0)) {
            console.log("Settlement executor:", settlementExecutor);
        }
    }

    function _deriveStateMachineId(string memory destCaip2) internal pure returns (bytes memory) {
        bytes32 key = keccak256(bytes(destCaip2));
        if (key == keccak256(bytes("eip155:42161"))) return bytes("EVM-42161");
        if (key == keccak256(bytes("eip155:8453"))) return bytes("EVM-8453");
        if (key == keccak256(bytes("eip155:137"))) return bytes("EVM-137");
        return bytes("");
    }

    function _postCheck(
        IHBTokenLaneGateway gateway,
        IHBTokenLaneRouter router,
        address sender,
        string memory destCaip2,
        uint8 bridgeType,
        address bridgeToken,
        bytes32 expectedAssetId
    ) internal view {
        if (gateway.defaultBridgeTypes(destCaip2) != bridgeType) revert WiringNotReady("defaultBridgeType mismatch");
        if (gateway.bridgeTokenByDestCaip2(destCaip2) != bridgeToken) revert WiringNotReady("bridgeTokenByDest mismatch");
        if (router.adapters(destCaip2, bridgeType) != sender) revert WiringNotReady("adapter not registered");
        if (!router.isRouteConfigured(destCaip2, bridgeType)) revert WiringNotReady("router route not configured");
        if (!HyperbridgeTokenGatewaySender(sender).isRouteConfigured(destCaip2)) revert WiringNotReady("sender route not configured");
        if (HyperbridgeTokenGatewaySender(sender).assetIdsByToken(bridgeToken) != expectedAssetId) {
            revert WiringNotReady("sender assetId mismatch");
        }
    }

}
