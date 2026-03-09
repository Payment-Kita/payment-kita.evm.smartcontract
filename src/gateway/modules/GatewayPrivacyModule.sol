// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../../interfaces/IGatewayPrivacyModule.sol";

interface IStealthEscrowForwarder {
    function forwardToken(address token, address receiver, uint256 amount) external;
}

contract GatewayPrivacyModule is Ownable, IGatewayPrivacyModule {
    error UnauthorizedGateway(address caller);
    error InvalidPrivacyForwardData();

    mapping(address => bool) public authorizedGateway;
    event AuthorizedGatewayUpdated(address indexed gateway, bool allowed);
    event PrivacyIntentRecorded(
        bytes32 indexed paymentId,
        bytes32 indexed intentId,
        address indexed stealthReceiver,
        address sender
    );
    event PrivacyForwardRecorded(
        bytes32 indexed paymentId,
        address indexed stealthReceiver,
        address indexed finalReceiver,
        address token,
        uint256 amount,
        address caller
    );
    event PrivacyForwardExecutionRequested(
        bytes32 indexed paymentId,
        address indexed stealthReceiver,
        address indexed finalReceiver,
        address token,
        uint256 amount,
        address caller,
        bool sameChain
    );

    constructor() Ownable(msg.sender) {}

    function setAuthorizedGateway(address gateway, bool allowed) external onlyOwner {
        authorizedGateway[gateway] = allowed;
        emit AuthorizedGatewayUpdated(gateway, allowed);
    }

    function recordPrivacyIntent(
        bytes32 paymentId,
        bytes32 intentId,
        address stealthReceiver,
        address sender
    ) external override {
        if (!authorizedGateway[msg.sender]) revert UnauthorizedGateway(msg.sender);
        emit PrivacyIntentRecorded(paymentId, intentId, stealthReceiver, sender);
    }

    function recordPrivacyForward(
        bytes32 paymentId,
        address stealthReceiver,
        address finalReceiver,
        address token,
        uint256 amount,
        address caller
    ) external override {
        if (!authorizedGateway[msg.sender]) revert UnauthorizedGateway(msg.sender);
        emit PrivacyForwardRecorded(paymentId, stealthReceiver, finalReceiver, token, amount, caller);
    }

    function forwardFromStealth(
        bytes32 paymentId,
        address stealthReceiver,
        address finalReceiver,
        address token,
        uint256 amount,
        address caller,
        bool sameChain
    ) external override {
        if (!authorizedGateway[msg.sender]) revert UnauthorizedGateway(msg.sender);
        if (
            stealthReceiver == address(0) ||
            finalReceiver == address(0) ||
            stealthReceiver == finalReceiver ||
            token == address(0) ||
            amount == 0 ||
            stealthReceiver.code.length == 0
        ) {
            revert InvalidPrivacyForwardData();
        }

        emit PrivacyForwardExecutionRequested(
            paymentId,
            stealthReceiver,
            finalReceiver,
            token,
            amount,
            caller,
            sameChain
        );

        IStealthEscrowForwarder(stealthReceiver).forwardToken(token, finalReceiver, amount);

        emit PrivacyForwardRecorded(paymentId, stealthReceiver, finalReceiver, token, amount, caller);
    }
}
