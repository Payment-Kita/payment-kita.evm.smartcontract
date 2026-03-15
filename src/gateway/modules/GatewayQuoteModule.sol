// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../../interfaces/IGatewayQuoteModule.sol";
import "../../interfaces/IBridgeAdapter.sol";
import "../../interfaces/ISwapper.sol";
import "../../PaymentKitaRouter.sol";

contract GatewayQuoteModule is Ownable, IGatewayQuoteModule {
    constructor() Ownable(msg.sender) {}

    function quotePaymentFeeSafe(
        address router,
        string calldata destChainId,
        uint8 bridgeType,
        IBridgeAdapter.BridgeMessage calldata message
    ) external view override returns (bool ok, uint256 feeNative, string memory reason) {
        return PaymentKitaRouter(router).quotePaymentFeeSafe(destChainId, bridgeType, message);
    }

    function quoteBridgeForV2(
        address router,
        address swapper,
        bool enableSourceSideSwap,
        string calldata destChainId,
        bytes calldata receiverBytes,
        address sourceToken,
        address destToken,
        uint256 amountInSource,
        uint256 minDestAmountOut,
        uint8 bridgeType,
        address bridgeTokenSource
    ) external view override returns (bool ok, uint256 feeNative, string memory reason) {
        PaymentKitaRouter paymentRouter = PaymentKitaRouter(router);
        address effectiveSourceToken = sourceToken;
        uint256 effectiveAmount = amountInSource;

        if (sourceToken != bridgeTokenSource) {
            if (!enableSourceSideSwap) {
                return (false, 0, "source_side_swap_disabled");
            }
            if (swapper == address(0)) {
                return (false, 0, "swapper_not_configured");
            }

            (bool routeExists,,) = ISwapper(swapper).findRoute(sourceToken, bridgeTokenSource);
            if (!routeExists) {
                return (false, 0, "no_route_to_bridge_token");
            }

            try ISwapper(swapper).getQuote(sourceToken, bridgeTokenSource, amountInSource) returns (uint256 quotedBridgeAmount) {
                effectiveSourceToken = bridgeTokenSource;
                effectiveAmount = quotedBridgeAmount;
            } catch {
                return (false, 0, "source_swap_quote_failed");
            }
        } else {
            effectiveSourceToken = bridgeTokenSource;
        }

        if (
            paymentRouter.bridgeModes(bridgeType) == PaymentKitaRouter.BridgeMode.TOKEN_BRIDGE &&
            effectiveSourceToken != destToken &&
            !paymentRouter.tokenBridgeSupportsDestSwap(bridgeType)
        ) {
            return (false, 0, "TOKEN_BRIDGE requires same token");
        }

        address receiver = abi.decode(receiverBytes, (address));
        require(receiver != address(0), "Invalid receiver address");

        IBridgeAdapter.BridgeMessage memory message = IBridgeAdapter.BridgeMessage({
            paymentId: bytes32(0),
            receiver: receiver,
            sourceToken: effectiveSourceToken,
            destToken: destToken,
            amount: effectiveAmount,
            destChainId: destChainId,
            minAmountOut: minDestAmountOut,
            payer: address(0)
        });

        return PaymentKitaRouter(router).quotePaymentFeeSafe(destChainId, bridgeType, message);
    }

    function quoteBridgeForV1(
        address router,
        string calldata destChainId,
        bytes calldata receiverBytes,
        address sourceToken,
        address destToken,
        uint256 amount,
        uint256 minAmountOut,
        uint8 bridgeType
    ) external view override returns (bool ok, uint256 feeNative, string memory reason) {
        PaymentKitaRouter paymentRouter = PaymentKitaRouter(router);
        if (
            paymentRouter.bridgeModes(bridgeType) == PaymentKitaRouter.BridgeMode.TOKEN_BRIDGE &&
            sourceToken != destToken &&
            !paymentRouter.tokenBridgeSupportsDestSwap(bridgeType)
        ) {
            return (false, 0, "TOKEN_BRIDGE requires same token");
        }

        address receiver = abi.decode(receiverBytes, (address));
        require(receiver != address(0), "Invalid receiver address");

        IBridgeAdapter.BridgeMessage memory message = IBridgeAdapter.BridgeMessage({
            paymentId: bytes32(0),
            receiver: receiver,
            sourceToken: sourceToken,
            destToken: destToken,
            amount: amount,
            destChainId: destChainId,
            minAmountOut: minAmountOut,
            payer: address(0)
        });

        return PaymentKitaRouter(router).quotePaymentFeeSafe(destChainId, bridgeType, message);
    }
}
