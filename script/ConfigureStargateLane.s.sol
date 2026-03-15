// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/integrations/stargate/StargateSenderAdapter.sol";
import "../src/integrations/stargate/StargateReceiverAdapter.sol";

interface IStargateLaneGateway {
    function router() external view returns (address);
    function vault() external view returns (address);
    function swapper() external view returns (address);
    function setAuthorizedAdapter(address adapter, bool authorized) external;
    function setDefaultBridgeType(string calldata destChainId, uint8 bridgeType) external;
    function defaultBridgeTypes(string calldata destChainId) external view returns (uint8);
}

interface IStargateLaneRouter {
    function registerAdapter(string calldata destChainId, uint8 bridgeType, address adapter) external;
    function getAdapter(string calldata destChainId, uint8 bridgeType) external view returns (address);
}

interface IStargateLaneVault {
    function setAuthorizedSpender(address spender, bool authorized) external;
    function authorizedSpenders(address spender) external view returns (bool);
}

interface IStargateLaneSwapper {
    function setAuthorizedCaller(address caller, bool allowed) external;
    function authorizedCallers(address caller) external view returns (bool);
}

contract ConfigureStargateLane is Script {
    uint8 internal constant BRIDGE_TYPE_STARGATE = 2;

    error MissingGateway();
    error MissingStargatePool();
    error MissingDestCaip2();
    error MissingRemoteReceiver();
    error MissingDstEid();
    error MissingSrcEid();
    error MissingReceivedToken();
    error InvalidCoreAddress(string name);
    error WiringNotReady(string reason);

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        bool deployOnly = vm.envOr("STARGATE_DEPLOY_ONLY", false);

        address gatewayAddr = vm.envAddress("STARGATE_GATEWAY_CONTRACT");
        if (gatewayAddr == address(0)) revert MissingGateway();

        address stargatePool = vm.envOr("STARGATE_POOL", address(0));
        if (!deployOnly && stargatePool == address(0)) revert MissingStargatePool();

        string memory destCaip2 = vm.envOr("STARGATE_DEST_CAIP2", string(""));
        if (!deployOnly && bytes(destCaip2).length == 0) revert MissingDestCaip2();

        bytes32 remoteReceiver = _parseBytes32OrZero(vm.envOr("STARGATE_REMOTE_RECEIVER_BYTES32", string("")));
        if (!deployOnly && remoteReceiver == bytes32(0)) revert MissingRemoteReceiver();

        uint32 dstEid = uint32(vm.envOr("STARGATE_DST_EID", uint256(0)));
        if (!deployOnly && dstEid == 0) revert MissingDstEid();

        uint32 srcEid = uint32(vm.envOr("STARGATE_SRC_EID", uint256(0)));
        if (!deployOnly && srcEid == 0) revert MissingSrcEid();

        address receivedToken = vm.envOr("STARGATE_RECEIVED_TOKEN", address(0));
        if (!deployOnly && receivedToken == address(0)) revert MissingReceivedToken();

        address trustedStargate = vm.envOr("STARGATE_TRUSTED_SOURCE_POOL", address(0));
        address existingSender = vm.envOr("STARGATE_SENDER", address(0));
        address existingReceiver = vm.envOr("STARGATE_RECEIVER", address(0));
        bool setDefaultBridgeType = vm.envOr("STARGATE_SET_DEFAULT_BRIDGE", false);
        bool deauthorizeOld = vm.envOr("STARGATE_DEAUTHORIZE_OLD", false);
        address oldSender = vm.envOr("STARGATE_OLD_SENDER", address(0));
        address oldReceiver = vm.envOr("STARGATE_OLD_RECEIVER", address(0));
        uint128 composeGasLimit = uint128(vm.envOr("STARGATE_COMPOSE_GAS_LIMIT", uint256(250_000)));
        bytes memory extraOptions = _parseBytesOrEmpty(vm.envOr("STARGATE_EXTRA_OPTIONS_HEX", string("")));

        IStargateLaneGateway gateway = IStargateLaneGateway(gatewayAddr);
        address routerAddr = gateway.router();
        address vaultAddr = gateway.vault();
        address swapperAddr = gateway.swapper();

        if (routerAddr == address(0)) revert InvalidCoreAddress("router");
        if (vaultAddr == address(0)) revert InvalidCoreAddress("vault");
        if (swapperAddr == address(0)) revert InvalidCoreAddress("swapper");

        vm.startBroadcast(pk);

        address senderAddr = existingSender;
        address receiverAddr = existingReceiver;

        if (senderAddr == address(0)) {
            senderAddr = address(new StargateSenderAdapter(vaultAddr, gatewayAddr, routerAddr));
        }
        if (receiverAddr == address(0)) {
            receiverAddr = address(new StargateReceiverAdapter(vm.envAddress("STARGATE_ENDPOINT"), gatewayAddr, vaultAddr));
        }

        if (!deployOnly) {
            StargateSenderAdapter(senderAddr).setRoute(destCaip2, stargatePool, dstEid, remoteReceiver);
            StargateSenderAdapter(senderAddr).setDestinationComposeGasLimit(destCaip2, composeGasLimit);
            if (extraOptions.length > 0) {
                StargateSenderAdapter(senderAddr).setDestinationExtraOptions(destCaip2, extraOptions);
            }

            if (trustedStargate == address(0)) revert InvalidCoreAddress("trustedStargate");

            StargateReceiverAdapter(receiverAddr).setRoute(srcEid, trustedStargate, receivedToken);
            StargateReceiverAdapter(receiverAddr).setSwapper(swapperAddr);

            IStargateLaneVault(vaultAddr).setAuthorizedSpender(senderAddr, true);
            IStargateLaneVault(vaultAddr).setAuthorizedSpender(receiverAddr, true);
            IStargateLaneSwapper(swapperAddr).setAuthorizedCaller(receiverAddr, true);
            gateway.setAuthorizedAdapter(receiverAddr, true);
            IStargateLaneRouter(routerAddr).registerAdapter(destCaip2, BRIDGE_TYPE_STARGATE, senderAddr);

            if (setDefaultBridgeType) {
                gateway.setDefaultBridgeType(destCaip2, BRIDGE_TYPE_STARGATE);
            }

            if (deauthorizeOld) {
                if (oldReceiver != address(0)) {
                    gateway.setAuthorizedAdapter(oldReceiver, false);
                    IStargateLaneVault(vaultAddr).setAuthorizedSpender(oldReceiver, false);
                }
                if (oldSender != address(0)) {
                    IStargateLaneVault(vaultAddr).setAuthorizedSpender(oldSender, false);
                }
            }
        }

        vm.stopBroadcast();

        if (!deployOnly) {
            _postCheck(
                gateway,
                IStargateLaneRouter(routerAddr),
                IStargateLaneVault(vaultAddr),
                IStargateLaneSwapper(swapperAddr),
                senderAddr,
                receiverAddr,
                destCaip2,
                dstEid,
                srcEid,
                remoteReceiver,
                trustedStargate,
                receivedToken,
                setDefaultBridgeType
            );
        }

        console.log("ConfigureStargateLane complete.");
        console.log("Deploy only:", deployOnly);
        console.log("Gateway:", gatewayAddr);
        console.log("Sender:", senderAddr);
        console.log("Receiver:", receiverAddr);
        console.log("Dest CAIP2:", destCaip2);
        console.log("dstEid:", dstEid);
        console.log("srcEid:", srcEid);
        console.log("Stargate pool:", stargatePool);
        console.log("Received token:", receivedToken);
    }

    function _postCheck(
        IStargateLaneGateway gateway,
        IStargateLaneRouter router,
        IStargateLaneVault vault,
        IStargateLaneSwapper swapper,
        address senderAddr,
        address receiverAddr,
        string memory destCaip2,
        uint32 dstEid,
        uint32 srcEid,
        bytes32 remoteReceiver,
        address trustedStargate,
        address receivedToken,
        bool expectDefaultBridge
    ) internal view {
        if (router.getAdapter(destCaip2, BRIDGE_TYPE_STARGATE) != senderAddr) {
            revert WiringNotReady("router adapter mismatch");
        }
        if (!vault.authorizedSpenders(senderAddr)) revert WiringNotReady("vault sender auth missing");
        if (!vault.authorizedSpenders(receiverAddr)) revert WiringNotReady("vault receiver auth missing");
        if (!swapper.authorizedCallers(receiverAddr)) revert WiringNotReady("swapper caller missing");
        if (!StargateSenderAdapter(senderAddr).isRouteConfigured(destCaip2)) revert WiringNotReady("sender route not configured");
        if (StargateSenderAdapter(senderAddr).dstEids(destCaip2) != dstEid) revert WiringNotReady("dstEid mismatch");
        if (StargateSenderAdapter(senderAddr).destinationAdapters(destCaip2) != remoteReceiver) {
            revert WiringNotReady("destination adapter mismatch");
        }
        if (StargateReceiverAdapter(receiverAddr).trustedStargates(srcEid) != trustedStargate) {
            revert WiringNotReady("trusted stargate mismatch");
        }
        if (StargateReceiverAdapter(receiverAddr).receivedTokens(srcEid) != receivedToken) {
            revert WiringNotReady("received token mismatch");
        }
        if (!StargateReceiverAdapter(receiverAddr).allowedSourceEids(srcEid)) {
            revert WiringNotReady("source eid not allowed");
        }
        if (expectDefaultBridge && gateway.defaultBridgeTypes(destCaip2) != BRIDGE_TYPE_STARGATE) {
            revert WiringNotReady("default bridge mismatch");
        }
    }

    function _parseBytes32OrZero(string memory value) internal pure returns (bytes32) {
        if (bytes(value).length == 0) return bytes32(0);
        return vm.parseBytes32(value);
    }

    function _parseBytesOrEmpty(string memory value) internal pure returns (bytes memory) {
        if (bytes(value).length == 0) return bytes("");
        return vm.parseBytes(value);
    }
}
