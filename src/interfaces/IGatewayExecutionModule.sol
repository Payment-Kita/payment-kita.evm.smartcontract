// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IGatewayExecutionModule {
    function beforeRoute(
        bytes32 paymentId,
        string calldata destChainId,
        uint8 bridgeType,
        uint256 providedNativeFee,
        uint256 requiredNativeFee
    ) external pure;

    function onSameChainSettled(
        bytes32 paymentId,
        address receiver,
        address token,
        uint256 settledAmount
    ) external;

    function onIncomingFinalized(
        bytes32 paymentId,
        uint256 amount
    ) external;
}
