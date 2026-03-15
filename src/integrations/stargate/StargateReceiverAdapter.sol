// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../PaymentKitaGateway.sol";
import "../../vaults/PaymentKitaVault.sol";
import "../../TokenSwapper.sol";
import "../RescuableAdapter.sol";
import "./StargateComposeCodec.sol";

contract StargateReceiverAdapter is RescuableAdapter {
    using SafeERC20 for IERC20;

    uint8 public constant PAYLOAD_VERSION_V1 = 1;
    uint256 internal constant PAYLOAD_V1_LENGTH = 10 * 32;
    uint256 internal constant LEGACY_PAYER_PREFIX_LENGTH = 32;

    address public endpoint;
    PaymentKitaGateway public gateway;
    PaymentKitaVault public vault;
    TokenSwapper public swapper;

    mapping(uint32 => address) public trustedStargates;
    mapping(uint32 => address) public receivedTokens;
    mapping(uint32 => bool) public allowedSourceEids;

    mapping(bytes32 => bool) public processedGuids;
    mapping(bytes32 => bytes) public failedComposeMessages;
    mapping(bytes32 => bytes) public failedComposeReasons;
    mapping(bytes32 => bytes32) public failedComposePaymentIds;
    mapping(bytes32 => uint256) public failedComposeRetryCount;

    event EndpointUpdated(address indexed oldEndpoint, address indexed newEndpoint);
    event GatewayUpdated(address indexed oldGateway, address indexed newGateway);
    event VaultUpdated(address indexed oldVault, address indexed newVault);
    event SwapperUpdated(address indexed oldSwapper, address indexed newSwapper);
    event StargateRouteSet(uint32 indexed srcEid, address indexed stargate, address indexed receivedToken);
    event SourceEidAllowed(uint32 indexed srcEid, bool allowed);
    event StargatePaymentReceived(
        bytes32 indexed guid,
        bytes32 indexed paymentId,
        uint32 indexed srcEid,
        address receiver,
        address settledToken,
        uint256 settledAmount,
        bool swapped
    );
    event StargateComposeProcessingFailed(bytes32 indexed guid, bytes32 indexed paymentId, uint32 indexed srcEid, bytes reason);
    event StargateComposeRetried(bytes32 indexed guid, bool success, bytes reason, uint256 retryCount);

    error UnauthorizedEndpoint(address caller);
    error UnauthorizedProcessor(address caller);
    error ComposeAlreadyProcessed(bytes32 guid);
    error UntrustedStargate(uint32 srcEid, address from, address expected);
    error UntrustedSourceEid(uint32 srcEid);
    error UnsupportedPayloadVersion(uint8 version);
    error InvalidPayload();
    error InvalidReceivedToken(uint32 srcEid);
    error InsufficientReceivedAmount(uint256 expected, uint256 available);
    error SwapperNotConfigured();
    error FailedComposeNotFound(bytes32 guid);

    constructor(address _endpoint, address _gateway, address _vault) Ownable(msg.sender) {
        if (_endpoint == address(0) || _gateway == address(0) || _vault == address(0)) revert InvalidPayload();
        endpoint = _endpoint;
        gateway = PaymentKitaGateway(_gateway);
        vault = PaymentKitaVault(_vault);
    }

    function setEndpoint(address _endpoint) external onlyOwner {
        if (_endpoint == address(0)) revert InvalidPayload();
        emit EndpointUpdated(endpoint, _endpoint);
        endpoint = _endpoint;
    }

    function setGateway(address _gateway) external onlyOwner {
        if (_gateway == address(0)) revert InvalidPayload();
        emit GatewayUpdated(address(gateway), _gateway);
        gateway = PaymentKitaGateway(_gateway);
    }

    function setVault(address _vault) external onlyOwner {
        if (_vault == address(0)) revert InvalidPayload();
        emit VaultUpdated(address(vault), _vault);
        vault = PaymentKitaVault(_vault);
    }

    function setSwapper(address _swapper) external onlyOwner {
        emit SwapperUpdated(address(swapper), _swapper);
        swapper = TokenSwapper(_swapper);
    }

    function setRoute(uint32 srcEid, address stargate, address receivedToken) external onlyOwner {
        if (srcEid == 0 || stargate == address(0) || receivedToken == address(0)) revert InvalidPayload();
        trustedStargates[srcEid] = stargate;
        receivedTokens[srcEid] = receivedToken;
        allowedSourceEids[srcEid] = true;
        emit StargateRouteSet(srcEid, stargate, receivedToken);
        emit SourceEidAllowed(srcEid, true);
    }

    function setSourceEidAllowed(uint32 srcEid, bool allowed) external onlyOwner {
        allowedSourceEids[srcEid] = allowed;
        emit SourceEidAllowed(srcEid, allowed);
    }

    function lzCompose(
        address _from,
        bytes32 _guid,
        bytes calldata _message,
        address,
        bytes calldata
    ) external payable {
        if (msg.sender != endpoint) revert UnauthorizedEndpoint(msg.sender);
        if (processedGuids[_guid]) revert ComposeAlreadyProcessed(_guid);

        uint32 srcEid = StargateComposeCodec.srcEid(_message);
        if (!allowedSourceEids[srcEid]) revert UntrustedSourceEid(srcEid);
        address trusted = trustedStargates[srcEid];
        if (trusted == address(0) || trusted != _from) revert UntrustedStargate(srcEid, _from, trusted);

        try this.processComposeEntry(_from, _guid, _message) {
            return;
        } catch (bytes memory reason) {
            bytes32 paymentId = _extractPaymentId(_message);
            failedComposeMessages[_guid] = abi.encode(_from, _message);
            failedComposeReasons[_guid] = reason;
            failedComposePaymentIds[_guid] = paymentId;
            emit StargateComposeProcessingFailed(_guid, paymentId, srcEid, reason);
        }
    }

    function processComposeEntry(address _from, bytes32 _guid, bytes calldata _message) external {
        if (msg.sender != address(this)) revert UnauthorizedProcessor(msg.sender);
        _processCompose(_from, _guid, _message);
    }

    function retryFailedCompose(bytes32 guid) external onlyOwner {
        bytes memory failed = failedComposeMessages[guid];
        if (failed.length == 0) revert FailedComposeNotFound(guid);

        (address from, bytes memory message) = abi.decode(failed, (address, bytes));
        uint256 retryCount = failedComposeRetryCount[guid] + 1;
        failedComposeRetryCount[guid] = retryCount;

        try this.processComposeEntry(from, guid, message) {
            delete failedComposeMessages[guid];
            delete failedComposeReasons[guid];
            delete failedComposeRetryCount[guid];
            delete failedComposePaymentIds[guid];
            emit StargateComposeRetried(guid, true, bytes(""), retryCount);
        } catch (bytes memory reason) {
            failedComposeReasons[guid] = reason;
            emit StargateComposeRetried(guid, false, reason, retryCount);
        }
    }

    function getFailedComposeStatus(
        bytes32 guid
    ) external view returns (bool exists, bytes32 paymentId, bytes memory reason, uint256 retryCount) {
        exists = failedComposeMessages[guid].length > 0;
        paymentId = failedComposePaymentIds[guid];
        reason = failedComposeReasons[guid];
        retryCount = failedComposeRetryCount[guid];
    }

    function _processCompose(address, bytes32 guid, bytes calldata message) internal {
        uint32 srcEid = StargateComposeCodec.srcEid(message);
        uint256 amountLD = StargateComposeCodec.amountLD(message);
        bytes calldata appPayload = _normalizeComposePayload(StargateComposeCodec.composeMsg(message));

        (
            uint8 version,
            bytes32 paymentId,
            address receiver,
            address destToken,
            uint256 minAmountOut,
            bool isPrivacy,
            bytes32 privacyIntentId,
            address privacyStealthReceiver,
            address privacyFinalReceiver,
            address privacySourceSender
        ) = abi.decode(
                appPayload,
                (uint8, bytes32, address, address, uint256, bool, bytes32, address, address, address)
            );

        if (version != PAYLOAD_VERSION_V1) revert UnsupportedPayloadVersion(version);
        if (receiver == address(0) || destToken == address(0) || amountLD == 0) revert InvalidPayload();

        if (isPrivacy) {
            if (
                privacyIntentId == bytes32(0) ||
                privacyStealthReceiver == address(0) ||
                privacyFinalReceiver == address(0) ||
                privacySourceSender == address(0)
            ) revert InvalidPayload();
            if (privacyStealthReceiver != receiver || privacyStealthReceiver == privacyFinalReceiver) revert InvalidPayload();
            gateway.registerIncomingPrivacyContext(
                paymentId,
                privacyIntentId,
                privacyStealthReceiver,
                privacyFinalReceiver,
                privacySourceSender
            );
        }

        address receivedToken = receivedTokens[srcEid];
        if (receivedToken == address(0)) revert InvalidReceivedToken(srcEid);

        uint256 available = IERC20(receivedToken).balanceOf(address(this));
        if (available < amountLD) revert InsufficientReceivedAmount(amountLD, available);

        processedGuids[guid] = true;

        uint256 settledAmount;
        address settledToken;
        bool swapped;
        if (receivedToken != destToken) {
            if (address(swapper) == address(0)) revert SwapperNotConfigured();
            IERC20(receivedToken).safeTransfer(address(vault), amountLD);
            settledAmount = swapper.swapFromVault(receivedToken, destToken, amountLD, minAmountOut, receiver);
            settledToken = destToken;
            swapped = true;
        } else {
            IERC20(receivedToken).safeTransfer(receiver, amountLD);
            settledAmount = amountLD;
            settledToken = receivedToken;
        }

        gateway.finalizeIncomingPayment(paymentId, receiver, settledToken, settledAmount);
        _tryFinalizePrivacyForward(paymentId, receiver, settledToken, settledAmount);

        emit StargatePaymentReceived(guid, paymentId, srcEid, receiver, settledToken, settledAmount, swapped);
    }

    function _tryFinalizePrivacyForward(
        bytes32 paymentId,
        address receiver,
        address token,
        uint256 amount
    ) internal {
        address stealthReceiver = gateway.privacyStealthByPayment(paymentId);
        if (stealthReceiver == address(0) || stealthReceiver != receiver) {
            return;
        }

        try gateway.finalizePrivacyForward(paymentId, token, amount) {
            return;
        } catch {
            try gateway.reportPrivacyForwardFailure(paymentId, "PRIVACY_FORWARD_FAILED") {
                return;
            } catch {
                return;
            }
        }
    }

    function _extractPaymentId(bytes calldata message) internal pure returns (bytes32 paymentId) {
        bytes calldata appPayload = _normalizeComposePayload(StargateComposeCodec.composeMsg(message));
        if (appPayload.length < 64) {
            return bytes32(0);
        }
        assembly {
            paymentId := calldataload(add(appPayload.offset, 32))
        }
    }

    function _normalizeComposePayload(bytes calldata rawPayload) internal pure returns (bytes calldata payload) {
        payload = rawPayload;
        if (rawPayload.length == PAYLOAD_V1_LENGTH + LEGACY_PAYER_PREFIX_LENGTH) {
            uint256 firstWord;
            assembly {
                firstWord := calldataload(rawPayload.offset)
            }
            if (firstWord != PAYLOAD_VERSION_V1) {
                payload = rawPayload[LEGACY_PAYER_PREFIX_LENGTH:];
            }
        }
    }
}
