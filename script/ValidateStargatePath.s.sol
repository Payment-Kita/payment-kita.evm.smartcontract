// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/interfaces/IBridgeAdapter.sol";
import "../src/integrations/stargate/StargateSenderAdapter.sol";
import "../src/integrations/stargate/StargateReceiverAdapter.sol";

interface IRouterStargateValidate {
    function hasAdapter(string memory destChainId, uint8 bridgeType) external view returns (bool);
    function getAdapter(string calldata destChainId, uint8 bridgeType) external view returns (address);
}

interface IGatewayStargateValidate {
    function defaultBridgeTypes(string calldata destChainId) external view returns (uint8);
}

contract ValidateStargatePath is Script {
    struct ValidateConfig {
        address router;
        address gateway;
        address receiver;
        string destCaip2;
        uint8 bridgeType;
        bool strict;
        uint32 dstEid;
        uint32 srcEid;
        bytes32 remoteReceiver;
        address trustedStargate;
        address receivedToken;
        address sourceToken;
        address destToken;
        uint256 amount;
    }

    function run() external {
        ValidateConfig memory cfg = _resolveValidateConfig();

        IRouterStargateValidate router = IRouterStargateValidate(cfg.router);
        bool has = router.hasAdapter(cfg.destCaip2, cfg.bridgeType);
        console.log("hasAdapter:", has);
        if (cfg.strict) require(has, "Stargate validate: adapter missing");
        if (!has) return;

        address sender = router.getAdapter(cfg.destCaip2, cfg.bridgeType);
        console.log("sender:", sender);

        bool configured = StargateSenderAdapter(sender).isRouteConfigured(cfg.destCaip2);
        console.log("sender route configured:", configured);
        if (cfg.strict) require(configured, "Stargate validate: sender route not configured");

        uint32 actualDstEid = StargateSenderAdapter(sender).dstEids(cfg.destCaip2);
        bytes32 actualRemoteReceiver = StargateSenderAdapter(sender).destinationAdapters(cfg.destCaip2);
        console.log("actualDstEid:", actualDstEid);
        console.logBytes32(actualRemoteReceiver);

        if (cfg.strict) {
            require(actualDstEid == cfg.dstEid, "Stargate validate: dstEid mismatch");
            require(actualRemoteReceiver == cfg.remoteReceiver, "Stargate validate: remote receiver mismatch");
        }

        if (cfg.receiver != address(0) && cfg.srcEid > 0) {
            address actualTrustedStargate = StargateReceiverAdapter(cfg.receiver).trustedStargates(cfg.srcEid);
            address actualReceivedToken = StargateReceiverAdapter(cfg.receiver).receivedTokens(cfg.srcEid);
            bool sourceAllowed = StargateReceiverAdapter(cfg.receiver).allowedSourceEids(cfg.srcEid);
            console.log("receiver trusted stargate:", actualTrustedStargate);
            console.log("receiver token:", actualReceivedToken);
            console.log("receiver allowed:", sourceAllowed);

            if (cfg.strict) {
                require(actualTrustedStargate == cfg.trustedStargate, "Stargate validate: trusted stargate mismatch");
                require(actualReceivedToken == cfg.receivedToken, "Stargate validate: received token mismatch");
                require(sourceAllowed, "Stargate validate: source eid not allowed");
            }
        }

        if (cfg.gateway != address(0)) {
            uint8 defaultBridge = IGatewayStargateValidate(cfg.gateway).defaultBridgeTypes(cfg.destCaip2);
            console.log("gateway default bridge:", defaultBridge);
        }

        if (cfg.sourceToken != address(0) && cfg.destToken != address(0) && cfg.amount > 0) {
            IBridgeAdapter.BridgeMessage memory message = IBridgeAdapter.BridgeMessage({
                paymentId: bytes32(0),
                receiver: address(0xBEEF),
                sourceToken: cfg.sourceToken,
                destToken: cfg.destToken,
                amount: cfg.amount,
                destChainId: cfg.destCaip2,
                minAmountOut: 0,
                payer: address(0xCAFE)
            });

            try StargateSenderAdapter(sender).quoteFee(message) returns (uint256 fee) {
                console.log("quoteFee:", fee);
                if (cfg.strict) require(fee > 0, "Stargate validate: quote zero");
            } catch {
                if (cfg.strict) revert("Stargate validate: quote reverted");
                console.log("quoteFee: reverted");
            }
        }
    }

    function _resolveValidateConfig() internal returns (ValidateConfig memory cfg) {
        string memory profile = vm.envOr("STARGATE_VALIDATE_PROFILE", string("auto"));

        if (_eq(profile, "base") || (_eq(profile, "auto") && block.chainid == 8453)) {
            cfg = ValidateConfig({
                router: vm.envOr("BASE_STARGATE_VALIDATE_ROUTER", 0x1b91B56aD3aA6B35e5EAe18EE19A42574A545802),
                gateway: vm.envOr("BASE_STARGATE_VALIDATE_GATEWAY", 0x08409b0fa63b0bCEb4c4B49DBf286ff943b60011),
                receiver: vm.envOr("BASE_STARGATE_VALIDATE_RECEIVER", address(0)),
                destCaip2: vm.envOr("BASE_STARGATE_VALIDATE_DEST_CAIP2", string("eip155:137")),
                bridgeType: uint8(vm.envOr("BASE_STARGATE_VALIDATE_BRIDGE_TYPE", uint256(2))),
                strict: vm.envOr("BASE_STARGATE_VALIDATE_STRICT", true),
                dstEid: uint32(vm.envOr("BASE_STARGATE_VALIDATE_DST_EID", uint256(30109))),
                srcEid: uint32(vm.envOr("BASE_STARGATE_VALIDATE_SRC_EID", uint256(30109))),
                remoteReceiver: _parseBytes32OrZero(vm.envOr("BASE_STARGATE_VALIDATE_REMOTE_RECEIVER", string(""))),
                trustedStargate: vm.envOr("BASE_STARGATE_VALIDATE_TRUSTED_STARGATE", address(0)),
                receivedToken: vm.envOr("BASE_STARGATE_VALIDATE_RECEIVED_TOKEN", address(0)),
                sourceToken: vm.envOr("BASE_STARGATE_VALIDATE_SOURCE_TOKEN", address(0)),
                destToken: vm.envOr("BASE_STARGATE_VALIDATE_DEST_TOKEN", address(0)),
                amount: vm.envOr("BASE_STARGATE_VALIDATE_AMOUNT", uint256(0))
            });
        } else if (_eq(profile, "polygon") || (_eq(profile, "auto") && block.chainid == 137)) {
            cfg = ValidateConfig({
                router: vm.envOr("POLYGON_STARGATE_VALIDATE_ROUTER", 0x84ff4D31f24110dB00a9d7F51B104fD7D6b3bF0F),
                gateway: vm.envOr("POLYGON_STARGATE_VALIDATE_GATEWAY", 0xcb5fC6c5E7895406b797B11F91AF67A07027a26F),
                receiver: vm.envOr("POLYGON_STARGATE_VALIDATE_RECEIVER", address(0)),
                destCaip2: vm.envOr("POLYGON_STARGATE_VALIDATE_DEST_CAIP2", string("eip155:8453")),
                bridgeType: uint8(vm.envOr("POLYGON_STARGATE_VALIDATE_BRIDGE_TYPE", uint256(2))),
                strict: vm.envOr("POLYGON_STARGATE_VALIDATE_STRICT", true),
                dstEid: uint32(vm.envOr("POLYGON_STARGATE_VALIDATE_DST_EID", uint256(30184))),
                srcEid: uint32(vm.envOr("POLYGON_STARGATE_VALIDATE_SRC_EID", uint256(30184))),
                remoteReceiver: _parseBytes32OrZero(vm.envOr("POLYGON_STARGATE_VALIDATE_REMOTE_RECEIVER", string(""))),
                trustedStargate: vm.envOr("POLYGON_STARGATE_VALIDATE_TRUSTED_STARGATE", address(0)),
                receivedToken: vm.envOr("POLYGON_STARGATE_VALIDATE_RECEIVED_TOKEN", address(0)),
                sourceToken: vm.envOr("POLYGON_STARGATE_VALIDATE_SOURCE_TOKEN", address(0)),
                destToken: vm.envOr("POLYGON_STARGATE_VALIDATE_DEST_TOKEN", address(0)),
                amount: vm.envOr("POLYGON_STARGATE_VALIDATE_AMOUNT", uint256(0))
            });
        } else if (_eq(profile, "arbitrum") || (_eq(profile, "auto") && block.chainid == 42161)) {
            cfg = ValidateConfig({
                router: vm.envOr("ARBITRUM_STARGATE_VALIDATE_ROUTER", 0x3722374b187E5400f4423DBc45AD73784604D275),
                gateway: vm.envOr("ARBITRUM_STARGATE_VALIDATE_GATEWAY", 0x259294aecdC0006B73b1281c30440A8179CFF44c),
                receiver: vm.envOr("ARBITRUM_STARGATE_VALIDATE_RECEIVER", address(0)),
                destCaip2: vm.envOr("ARBITRUM_STARGATE_VALIDATE_DEST_CAIP2", string("eip155:8453")),
                bridgeType: uint8(vm.envOr("ARBITRUM_STARGATE_VALIDATE_BRIDGE_TYPE", uint256(2))),
                strict: vm.envOr("ARBITRUM_STARGATE_VALIDATE_STRICT", true),
                dstEid: uint32(vm.envOr("ARBITRUM_STARGATE_VALIDATE_DST_EID", uint256(30184))),
                srcEid: uint32(vm.envOr("ARBITRUM_STARGATE_VALIDATE_SRC_EID", uint256(30184))),
                remoteReceiver: _parseBytes32OrZero(vm.envOr("ARBITRUM_STARGATE_VALIDATE_REMOTE_RECEIVER", string(""))),
                trustedStargate: vm.envOr("ARBITRUM_STARGATE_VALIDATE_TRUSTED_STARGATE", address(0)),
                receivedToken: vm.envOr("ARBITRUM_STARGATE_VALIDATE_RECEIVED_TOKEN", address(0)),
                sourceToken: vm.envOr("ARBITRUM_STARGATE_VALIDATE_SOURCE_TOKEN", address(0)),
                destToken: vm.envOr("ARBITRUM_STARGATE_VALIDATE_DEST_TOKEN", address(0)),
                amount: vm.envOr("ARBITRUM_STARGATE_VALIDATE_AMOUNT", uint256(0))
            });
        } else {
            revert("Stargate validate: unknown profile or chainid");
        }
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _parseBytes32OrZero(string memory value) internal pure returns (bytes32) {
        if (bytes(value).length == 0) return bytes32(0);
        return vm.parseBytes32(value);
    }
}
