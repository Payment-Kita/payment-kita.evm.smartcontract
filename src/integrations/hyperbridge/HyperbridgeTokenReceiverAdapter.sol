// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITokenGateway} from "@hyperbridge/core/apps/TokenGateway.sol";
import "../../PaymentKitaGateway.sol";
import "../../vaults/PaymentKitaVault.sol";
import "../../TokenSwapper.sol";
import "../RescuableAdapter.sol";

/**
 * @title HyperbridgeTokenReceiverAdapter
 * @notice Settlement executor for Hyperbridge Token Gateway bridgeType=3.
 * @dev Receives destination callback payload, settles direct transfer or destination swap,
 *      then finalizes payment and privacy-forward lifecycle in PaymentKitaGateway.
 */
contract HyperbridgeTokenReceiverAdapter is RescuableAdapter, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint8 public constant PAYLOAD_VERSION_V1 = 1;
    uint8 public constant PAYLOAD_VERSION_V2 = 2;

    ITokenGateway public tokenGateway;
    PaymentKitaGateway public gateway;
    PaymentKitaVault public vault;
    TokenSwapper public swapper;

    mapping(bytes32 => bool) public processedPayloads;

    event TokenGatewayUpdated(address indexed oldGateway, address indexed newGateway);
    event GatewayUpdated(address indexed oldGateway, address indexed newGateway);
    event VaultUpdated(address indexed oldVault, address indexed newVault);
    event SwapperUpdated(address indexed oldSwapper, address indexed newSwapper);
    event TokenGatewaySettlementExecuted(
        bytes32 indexed paymentId,
        bytes32 indexed payloadHash,
        bytes32 indexed assetId,
        address receiver,
        address bridgedToken,
        address settledToken,
        uint256 bridgedAmount,
        uint256 settledAmount,
        bool swapped
    );

    error NotTokenGateway();
    error ZeroAddress();
    error UnsupportedPayloadVersion(uint8 version);
    error InvalidPayload();
    error UnknownAsset(bytes32 assetId);
    error SettlementAlreadyProcessed(bytes32 payloadHash);
    error InsufficientBridgedAmount(uint256 expected, uint256 available);
    error SwapperNotConfigured();

    constructor(address _tokenGateway, address _gateway, address _vault) Ownable(msg.sender) {
        if (_tokenGateway == address(0) || _gateway == address(0) || _vault == address(0)) revert ZeroAddress();
        tokenGateway = ITokenGateway(_tokenGateway);
        gateway = PaymentKitaGateway(_gateway);
        vault = PaymentKitaVault(_vault);
    }

    function setTokenGateway(address _tokenGateway) external onlyOwner {
        if (_tokenGateway == address(0)) revert ZeroAddress();
        emit TokenGatewayUpdated(address(tokenGateway), _tokenGateway);
        tokenGateway = ITokenGateway(_tokenGateway);
    }

    function setGateway(address _gateway) external onlyOwner {
        if (_gateway == address(0)) revert ZeroAddress();
        emit GatewayUpdated(address(gateway), _gateway);
        gateway = PaymentKitaGateway(_gateway);
    }

    function setVault(address _vault) external onlyOwner {
        if (_vault == address(0)) revert ZeroAddress();
        emit VaultUpdated(address(vault), _vault);
        vault = PaymentKitaVault(_vault);
    }

    function setSwapper(address _swapper) external onlyOwner {
        emit SwapperUpdated(address(swapper), _swapper);
        swapper = TokenSwapper(_swapper);
    }

    /**
     * @notice Destination callback entrypoint called by Hyperbridge TokenGateway.
     * @param payload ABI-encoded payload:
     *        (uint8 version, bytes32 paymentId, address receiver, address destToken,
     *         uint256 minAmountOut, bytes32 assetId, uint256 bridgedAmount)
     */
    function onTokenGatewayPayload(bytes calldata payload) external nonReentrant {
        if (msg.sender != address(tokenGateway)) revert NotTokenGateway();

        bytes32 payloadHash = keccak256(payload);
        if (processedPayloads[payloadHash]) revert SettlementAlreadyProcessed(payloadHash);

        (
            ,
            bytes32 paymentId,
            address receiver,
            address destToken,
            uint256 minAmountOut,
            bytes32 assetId,
            uint256 bridgedAmount,
            bool isPrivacy,
            bytes32 privacyIntentId,
            address privacyStealthReceiver,
            address privacyFinalReceiver,
            address privacySourceSender
        ) = _decodePayload(payload);

        if (receiver == address(0) || destToken == address(0) || bridgedAmount == 0) revert InvalidPayload();

        if (isPrivacy) {
            if (
                privacyIntentId == bytes32(0) ||
                privacyStealthReceiver == address(0) ||
                privacyFinalReceiver == address(0) ||
                privacySourceSender == address(0)
            ) {
                revert InvalidPayload();
            }
            if (privacyStealthReceiver != receiver || privacyStealthReceiver == privacyFinalReceiver) {
                revert InvalidPayload();
            }
            gateway.registerIncomingPrivacyContext(
                paymentId,
                privacyIntentId,
                privacyStealthReceiver,
                privacyFinalReceiver,
                privacySourceSender
            );
        }

        address bridgedToken = tokenGateway.erc20(assetId);
        if (bridgedToken == address(0)) {
            bridgedToken = tokenGateway.erc6160(assetId);
        }
        if (bridgedToken == address(0)) revert UnknownAsset(assetId);

        uint256 available = IERC20(bridgedToken).balanceOf(address(this));
        if (available < bridgedAmount) revert InsufficientBridgedAmount(bridgedAmount, available);

        processedPayloads[payloadHash] = true;

        uint256 settledAmount;
        address settledToken;
        bool swapped;
        if (bridgedToken != destToken) {
            if (address(swapper) == address(0)) revert SwapperNotConfigured();

            IERC20(bridgedToken).safeTransfer(address(vault), bridgedAmount);
            settledAmount = swapper.swapFromVault(bridgedToken, destToken, bridgedAmount, minAmountOut, receiver);
            settledToken = destToken;
            swapped = true;
        } else {
            IERC20(bridgedToken).safeTransfer(receiver, bridgedAmount);
            settledAmount = bridgedAmount;
            settledToken = bridgedToken;
        }

        gateway.finalizeIncomingPayment(paymentId, receiver, settledToken, settledAmount);
        _tryFinalizePrivacyForward(paymentId, receiver, settledToken, settledAmount);

        emit TokenGatewaySettlementExecuted(
            paymentId,
            payloadHash,
            assetId,
            receiver,
            bridgedToken,
            settledToken,
            bridgedAmount,
            settledAmount,
            swapped
        );
    }

    function _decodePayload(
        bytes calldata payload
    )
        internal
        pure
        returns (
            uint8 version,
            bytes32 paymentId,
            address receiver,
            address destToken,
            uint256 minAmountOut,
            bytes32 assetId,
            uint256 bridgedAmount,
            bool isPrivacy,
            bytes32 privacyIntentId,
            address privacyStealthReceiver,
            address privacyFinalReceiver,
            address privacySourceSender
        )
    {
        if (payload.length < 32) revert InvalidPayload();
        version = uint8(bytes1(payload[31]));
        if (version == PAYLOAD_VERSION_V1) {
            (
                version,
                paymentId,
                receiver,
                destToken,
                minAmountOut,
                assetId,
                bridgedAmount
            ) = abi.decode(payload, (uint8, bytes32, address, address, uint256, bytes32, uint256));
            return (
                version,
                paymentId,
                receiver,
                destToken,
                minAmountOut,
                assetId,
                bridgedAmount,
                false,
                bytes32(0),
                address(0),
                address(0),
                address(0)
            );
        }
        if (version != PAYLOAD_VERSION_V2) revert UnsupportedPayloadVersion(version);
        return abi.decode(payload, (uint8, bytes32, address, address, uint256, bytes32, uint256, bool, bytes32, address, address, address));
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
            // Best-effort failure signal for monitoring and retries.
            try gateway.reportPrivacyForwardFailure(paymentId, "PRIVACY_FORWARD_FAILED") {
                return;
            } catch {
                return;
            }
        }
    }
}
