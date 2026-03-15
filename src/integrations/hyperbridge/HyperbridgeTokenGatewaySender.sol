// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITokenGateway, TeleportParams} from "@hyperbridge/core/apps/TokenGateway.sol";
import "../../interfaces/IBridgeAdapter.sol";
import "../../vaults/PaymentKitaVault.sol";

interface IHyperbridgeTokenGatewayReceiverEntry {
    function onTokenGatewayPayload(bytes calldata payload) external;
}

interface IPrivacyMetadataGateway {
    function privacyStealthByPayment(bytes32 paymentId) external view returns (address);
    function privacyFinalReceiverByPayment(bytes32 paymentId) external view returns (address);
    function privacyIntentByPayment(bytes32 paymentId) external view returns (bytes32);
}

/**
 * @title HyperbridgeTokenGatewaySender
 * @notice Hyperbridge Token Gateway sender adapter for bridgeType=3.
 * @dev Phase-2 sender-only implementation:
 * - Pulls bridge token liquidity from PaymentKitaVault
 * - Calls TokenGateway.teleport(...)
 * - Uses destination settlement executor to finalize regular/privacy flows.
 */
contract HyperbridgeTokenGatewaySender is IBridgeAdapter, Ownable {
    using SafeERC20 for IERC20;

    uint8 public constant PAYLOAD_VERSION_V2 = 2;

    PaymentKitaVault public vault;
    ITokenGateway public tokenGateway;
    IPrivacyMetadataGateway public gateway;
    address public router;

    uint64 public defaultTimeout = 3600;

    mapping(string => bytes) public stateMachineIds;
    mapping(string => address) public settlementExecutors;
    mapping(string => uint256) public nativeCosts;
    mapping(string => uint256) public relayerFees;
    mapping(string => uint64) public routeTimeouts;
    mapping(address => bytes32) public assetIdsByToken;

    event RouterUpdated(address indexed oldRouter, address indexed newRouter);
    event VaultUpdated(address indexed oldVault, address indexed newVault);
    event TokenGatewayUpdated(address indexed oldGateway, address indexed newGateway);
    event GatewayMetadataSourceUpdated(address indexed oldGateway, address indexed newGateway);
    event DefaultTimeoutUpdated(uint64 oldTimeout, uint64 newTimeout);
    event RouteStateMachineSet(string indexed destChainId, bytes stateMachineId);
    event RouteSettlementExecutorSet(string indexed destChainId, address indexed settlementExecutor);
    event RouteNativeCostSet(string indexed destChainId, uint256 nativeCost);
    event RouteRelayerFeeSet(string indexed destChainId, uint256 relayerFee);
    event RouteTimeoutSet(string indexed destChainId, uint64 timeout);
    event TokenAssetIdSet(address indexed token, bytes32 indexed assetId);
    event TokenGatewayTeleportSent(
        bytes32 indexed paymentId,
        bytes32 indexed messageId,
        string indexed destChainId,
        address token,
        uint256 amount,
        bytes32 assetId,
        address receiver,
        address settlementExecutor
    );

    error NotRouter();
    error ZeroAddress();
    error InvalidTimeout();
    error RouteNotConfigured(string destChainId);
    error SettlementExecutorNotConfigured(string destChainId);
    error UnknownAsset(address token);
    error PrivacyContextInvalid();
    error PrivacyReceiverMismatch(address expectedStealth, address messageReceiver);
    error InsufficientNativeFee(uint256 required, uint256 provided);
    error InvalidReceiver();

    constructor(address _vault, address _tokenGateway, address _gateway, address _router) Ownable(msg.sender) {
        if (_vault == address(0) || _tokenGateway == address(0) || _gateway == address(0) || _router == address(0)) {
            revert ZeroAddress();
        }
        vault = PaymentKitaVault(_vault);
        tokenGateway = ITokenGateway(_tokenGateway);
        gateway = IPrivacyMetadataGateway(_gateway);
        router = _router;
    }

    modifier onlyRouter() {
        _onlyRouter();
        _;
    }

    function _onlyRouter() internal view {
        if (msg.sender != router) revert NotRouter();
    }

    function setRouter(address _router) external onlyOwner {
        if (_router == address(0)) revert ZeroAddress();
        emit RouterUpdated(router, _router);
        router = _router;
    }

    function setVault(address _vault) external onlyOwner {
        if (_vault == address(0)) revert ZeroAddress();
        emit VaultUpdated(address(vault), _vault);
        vault = PaymentKitaVault(_vault);
    }

    function setTokenGateway(address _tokenGateway) external onlyOwner {
        if (_tokenGateway == address(0)) revert ZeroAddress();
        emit TokenGatewayUpdated(address(tokenGateway), _tokenGateway);
        tokenGateway = ITokenGateway(_tokenGateway);
    }

    function setGateway(address _gateway) external onlyOwner {
        if (_gateway == address(0)) revert ZeroAddress();
        emit GatewayMetadataSourceUpdated(address(gateway), _gateway);
        gateway = IPrivacyMetadataGateway(_gateway);
    }

    function setDefaultTimeout(uint64 _timeout) external onlyOwner {
        if (_timeout < 300) revert InvalidTimeout();
        emit DefaultTimeoutUpdated(defaultTimeout, _timeout);
        defaultTimeout = _timeout;
    }

    function setStateMachineId(string calldata destChainId, bytes calldata stateMachineId) external onlyOwner {
        stateMachineIds[destChainId] = stateMachineId;
        emit RouteStateMachineSet(destChainId, stateMachineId);
    }

    function setRouteSettlementExecutor(string calldata destChainId, address settlementExecutor) external onlyOwner {
        if (settlementExecutor == address(0)) revert ZeroAddress();
        settlementExecutors[destChainId] = settlementExecutor;
        emit RouteSettlementExecutorSet(destChainId, settlementExecutor);
    }

    function setNativeCost(string calldata destChainId, uint256 nativeCost) external onlyOwner {
        nativeCosts[destChainId] = nativeCost;
        emit RouteNativeCostSet(destChainId, nativeCost);
    }

    function setRelayerFee(string calldata destChainId, uint256 relayerFee) external onlyOwner {
        relayerFees[destChainId] = relayerFee;
        emit RouteRelayerFeeSet(destChainId, relayerFee);
    }

    function setRouteTimeout(string calldata destChainId, uint64 timeoutSec) external onlyOwner {
        if (timeoutSec != 0 && timeoutSec < 300) revert InvalidTimeout();
        routeTimeouts[destChainId] = timeoutSec;
        emit RouteTimeoutSet(destChainId, timeoutSec);
    }

    function setTokenAssetId(address token, bytes32 assetId) external onlyOwner {
        if (token == address(0) || assetId == bytes32(0)) revert ZeroAddress();
        assetIdsByToken[token] = assetId;
        emit TokenAssetIdSet(token, assetId);
    }

    function quoteFee(BridgeMessage calldata message) external view override returns (uint256 fee) {
        return nativeCosts[message.destChainId];
    }

    function sendMessage(BridgeMessage calldata message) external payable override onlyRouter returns (bytes32 messageId) {
        bytes memory stateMachineId = stateMachineIds[message.destChainId];
        if (stateMachineId.length == 0) revert RouteNotConfigured(message.destChainId);
        if (message.receiver == address(0)) revert InvalidReceiver();

        address settlementExecutor = settlementExecutors[message.destChainId];
        if (settlementExecutor == address(0)) revert SettlementExecutorNotConfigured(message.destChainId);

        bytes32 assetId = assetIdsByToken[message.sourceToken];
        if (assetId == bytes32(0)) revert UnknownAsset(message.sourceToken);

        uint256 requiredNative = nativeCosts[message.destChainId];
        if (msg.value < requiredNative) revert InsufficientNativeFee(requiredNative, msg.value);

        // Pull bridge token from vault, then approve token gateway to custody/burn.
        vault.pushTokens(message.sourceToken, address(this), message.amount);
        IERC20(message.sourceToken).forceApprove(address(tokenGateway), 0);
        IERC20(message.sourceToken).forceApprove(address(tokenGateway), message.amount);

        address privacyStealth = gateway.privacyStealthByPayment(message.paymentId);
        bool isPrivacy = privacyStealth != address(0);
        bytes32 privacyIntentId = bytes32(0);
        address privacyFinalReceiver = address(0);
        if (isPrivacy) {
            if (privacyStealth != message.receiver) {
                revert PrivacyReceiverMismatch(privacyStealth, message.receiver);
            }
            privacyIntentId = gateway.privacyIntentByPayment(message.paymentId);
            privacyFinalReceiver = gateway.privacyFinalReceiverByPayment(message.paymentId);
            if (privacyIntentId == bytes32(0) || privacyFinalReceiver == address(0) || privacyFinalReceiver == privacyStealth) {
                revert PrivacyContextInvalid();
            }
        }

        bytes memory settlementPayload = abi.encode(
            PAYLOAD_VERSION_V2,
            message.paymentId,
            message.receiver,
            message.destToken,
            message.minAmountOut,
            assetId,
            message.amount,
            isPrivacy,
            privacyIntentId,
            privacyStealth,
            privacyFinalReceiver,
            message.payer
        );

        TeleportParams memory params = TeleportParams({
            amount: message.amount,
            relayerFee: relayerFees[message.destChainId],
            assetId: assetId,
            redeem: true,
            to: _addressToBytes32(settlementExecutor),
            dest: stateMachineId,
            timeout: _effectiveTimeout(message.destChainId),
            nativeCost: requiredNative,
            data: abi.encodeCall(IHyperbridgeTokenGatewayReceiverEntry.onTokenGatewayPayload, (settlementPayload))
        });

        tokenGateway.teleport{value: msg.value}(params);

        messageId = keccak256(
            abi.encode(
                message.paymentId,
                message.destChainId,
                message.sourceToken,
                message.amount,
                message.receiver,
                assetId,
                settlementExecutor,
                keccak256(settlementPayload),
                block.number
            )
        );

        emit TokenGatewayTeleportSent(
            message.paymentId,
            messageId,
            message.destChainId,
            message.sourceToken,
            message.amount,
            assetId,
            message.receiver,
            settlementExecutor
        );
    }

    function isRouteConfigured(string calldata destChainId) external view override returns (bool) {
        bytes memory stateMachineId = stateMachineIds[destChainId];
        if (stateMachineId.length == 0) return false;
        if (settlementExecutors[destChainId] == address(0)) return false;

        // Require explicit instance mapping. Do not enforce remote != self, because
        // some deployments intentionally use the same gateway address across chains.
        try tokenGateway.instance(stateMachineId) returns (address remoteGateway) {
            return remoteGateway != address(0);
        } catch {
            return false;
        }
    }

    function getRouteConfig(
        string calldata destChainId
    ) external view override returns (bool configured, bytes memory configA, bytes memory configB) {
        bytes memory stateMachineId = stateMachineIds[destChainId];
        address settlementExecutor = settlementExecutors[destChainId];
        address remoteGateway = address(0);
        if (stateMachineId.length > 0) {
            try tokenGateway.instance(stateMachineId) returns (address resolved) {
                remoteGateway = resolved;
            } catch {}
        }

        configured =
            stateMachineId.length > 0 &&
            settlementExecutor != address(0) &&
            remoteGateway != address(0);
        configA = stateMachineId;
        configB = abi.encode(
            nativeCosts[destChainId],
            relayerFees[destChainId],
            routeTimeouts[destChainId],
            _effectiveTimeout(destChainId),
            remoteGateway,
            settlementExecutor
        );
    }

    function _effectiveTimeout(string calldata destChainId) internal view returns (uint64) {
        uint64 routeTimeout = routeTimeouts[destChainId];
        if (routeTimeout != 0) {
            return routeTimeout;
        }
        return defaultTimeout;
    }

    function _addressToBytes32(address account) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(account)));
    }
}
