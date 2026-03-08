// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../../interfaces/IGatewayExecutionModule.sol";

contract GatewayExecutionModule is Ownable, IGatewayExecutionModule {
    error InsufficientNativeFee(uint256 provided, uint256 required);

    constructor() Ownable(msg.sender) {}

    event SameChainSettled(bytes32 indexed paymentId, address indexed receiver, address indexed token, uint256 settledAmount);
    event IncomingFinalized(bytes32 indexed paymentId, uint256 amount);

    function beforeRoute(
        bytes32 paymentId,
        string calldata destChainId,
        uint8 bridgeType,
        uint256 providedNativeFee,
        uint256 requiredNativeFee
    ) external pure override {
        if (providedNativeFee < requiredNativeFee) {
            revert InsufficientNativeFee(providedNativeFee, requiredNativeFee);
        }
        paymentId;
        destChainId;
        bridgeType;
    }

    function onSameChainSettled(
        bytes32 paymentId,
        address receiver,
        address token,
        uint256 settledAmount
    ) external override {
        emit SameChainSettled(paymentId, receiver, token, settledAmount);
    }

    function onIncomingFinalized(
        bytes32 paymentId,
        uint256 amount
    ) external override {
        emit IncomingFinalized(paymentId, amount);
    }
}
