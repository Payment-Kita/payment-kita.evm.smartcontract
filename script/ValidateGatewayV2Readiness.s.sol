// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/interfaces/IPaymentKitaGateway.sol";

interface IGatewayV2Readiness is IPaymentKitaGateway {
    function defaultBridgeTypes(string calldata destChainId) external view returns (uint8);
    function bridgeTokenByDestCaip2(string calldata destChainId) external view returns (address);
}

interface IRouterV2Readiness {
    function hasAdapter(string calldata destChainId, uint8 bridgeType) external view returns (bool);
    function isRouteConfigured(string calldata destChainId, uint8 bridgeType) external view returns (bool);
}

contract ValidateGatewayV2Readiness is Script {
    function run() external {
        address gatewayAddr = vm.envAddress("GW_VALIDATE_GATEWAY");
        address routerAddr = vm.envAddress("GW_VALIDATE_ROUTER");
        string memory destCaip2 = vm.envString("GW_VALIDATE_DEST_CAIP2");
        address sourceToken = vm.envAddress("GW_VALIDATE_SOURCE_TOKEN");
        address destToken = vm.envAddress("GW_VALIDATE_DEST_TOKEN");
        address receiver = vm.envAddress("GW_VALIDATE_RECEIVER");
        uint256 amount = vm.envUint("GW_VALIDATE_AMOUNT");
        address bridgeTokenOverride = vm.envOr("GW_VALIDATE_BRIDGE_TOKEN_SOURCE", address(0));
        uint8 bridgeOption = uint8(vm.envOr("GW_VALIDATE_BRIDGE_OPTION", uint256(255)));
        uint8 mode = uint8(vm.envOr("GW_VALIDATE_MODE", uint256(0))); // 0 regular, 1 privacy

        IGatewayV2Readiness gateway = IGatewayV2Readiness(gatewayAddr);
        IRouterV2Readiness router = IRouterV2Readiness(routerAddr);

        uint8 defaultBridge = gateway.defaultBridgeTypes(destCaip2);
        uint8 effectiveBridge = bridgeOption == 255 ? defaultBridge : bridgeOption;
        bool hasAdapter = router.hasAdapter(destCaip2, effectiveBridge);
        bool routeConfigured = router.isRouteConfigured(destCaip2, effectiveBridge);
        address laneBridgeToken = gateway.bridgeTokenByDestCaip2(destCaip2);

        IPaymentKitaGateway.PaymentRequestV2 memory req;
        req.destChainIdBytes = bytes(destCaip2);
        req.receiverBytes = abi.encode(receiver);
        req.sourceToken = sourceToken;
        req.bridgeTokenSource = bridgeTokenOverride;
        req.destToken = destToken;
        req.amountInSource = amount;
        req.minBridgeAmountOut = 0;
        req.minDestAmountOut = 0;
        req.mode = mode == 1 ? IPaymentKitaGateway.PaymentMode.PRIVACY : IPaymentKitaGateway.PaymentMode.REGULAR;
        req.bridgeOption = bridgeOption;

        (
            uint256 platformFee,
            uint256 bridgeFeeNative,
            uint256 totalSourceTokenRequired,
            uint8 bridgeType,
            bool bridgeQuoteOk,
            string memory bridgeQuoteReason
        ) = gateway.quotePaymentCost(req);

        (address approvalToken, uint256 approvalAmount, uint256 requiredNativeFee) = gateway.previewApproval(req);

        console.log("Gateway V2 readiness");
        console.log("gateway:", gatewayAddr);
        console.log("router:", routerAddr);
        console.log("dest:", destCaip2);
        console.log("defaultBridge:", defaultBridge);
        console.log("effectiveBridge:", effectiveBridge);
        console.log("hasAdapter:", hasAdapter);
        console.log("routeConfigured:", routeConfigured);
        console.log("laneBridgeToken:", laneBridgeToken);
        console.log("quoteBridgeType:", bridgeType);
        console.log("quoteOk:", bridgeQuoteOk);
        console.log("quoteReason:", bridgeQuoteReason);
        console.log("platformFee:", platformFee);
        console.log("bridgeFeeNative:", bridgeFeeNative);
        console.log("totalSourceTokenRequired:", totalSourceTokenRequired);
        console.log("approvalToken:", approvalToken);
        console.log("approvalAmount:", approvalAmount);
        console.log("requiredNativeFee(buffered):", requiredNativeFee);
    }
}
