// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IBridgeAdapter.sol";

interface IGatewayQuoteModule {
    function quotePaymentFeeSafe(
        address router,
        string calldata destChainId,
        uint8 bridgeType,
        IBridgeAdapter.BridgeMessage calldata message
    ) external view returns (bool ok, uint256 feeNative, string memory reason);

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
    ) external view returns (bool ok, uint256 feeNative, string memory reason);

    function quoteBridgeForV1(
        address router,
        string calldata destChainId,
        bytes calldata receiverBytes,
        address sourceToken,
        address destToken,
        uint256 amount,
        uint256 minAmountOut,
        uint8 bridgeType
    ) external view returns (bool ok, uint256 feeNative, string memory reason);
}
