// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPayChain
 * @notice Interface for PayChain cross-chain payment gateway
 * @dev Base interface for all PayChain implementations
 */
interface IPayChainGateway {
    enum PaymentMode {
        REGULAR,
        PRIVACY
    }

    enum PaymentStatus {
        Pending,
        Processing,
        Completed,
        Failed,
        Refunded
    }

    struct Payment {
        address sender;
        address receiver;
        string sourceChainId;
        string destChainId;
        address sourceToken;
        address destToken;
        uint256 amount;
        uint256 fee;
        PaymentStatus status;
        uint256 createdAt;
    }

    struct PaymentRequestV2 {
        bytes destChainIdBytes;
        bytes receiverBytes;
        address sourceToken;
        address bridgeTokenSource;
        address destToken;
        uint256 amountInSource;
        uint256 minBridgeAmountOut;
        uint256 minDestAmountOut;
        PaymentMode mode;
        // Sentinel bridge option for V2 request:
        // 255 => use default bridge mapping in gateway
        // 0   => Hyperbridge
        // 1   => CCIP
        // 2   => LayerZero
        uint8 bridgeOption;
    }

    struct PrivateRouting {
        bytes32 intentId;
        address stealthReceiver;
    }

    // ============ Events ============

    event PaymentCreated(
        bytes32 indexed paymentId,
        address indexed sender,
        address indexed receiver,
        string destChainId,
        address sourceToken,
        address destToken,
        uint256 amount,
        uint256 fee,
        string bridgeType
    );

    event PaymentExecuted(bytes32 indexed paymentId, bytes32 messageId);

    event PaymentCompleted(bytes32 indexed paymentId, uint256 destAmount);

    event PaymentRefunded(bytes32 indexed paymentId, uint256 refundAmount);

    event PaymentRequestCreated(
        bytes32 indexed requestId,
        address indexed merchant,
        address indexed receiver,
        address token,
        uint256 amount,
        uint256 expiresAt
    );

    event RequestPaymentReceived(
        bytes32 indexed requestId,
        address indexed payer,
        address indexed receiver,
        address token,
        uint256 amount
    );

    // ============ Functions ============

    function createPayment(
        bytes calldata destChainId,
        bytes calldata receiver,
        address sourceToken,
        address destToken,
        uint256 amount
    ) external payable returns (bytes32 paymentId);

    /// @notice Create cross-chain payment with slippage protection
    /// @param destChainId Destination chain ID (CAIP-2 encoded)
    /// @param receiver Receiver address (encoded)
    /// @param sourceToken Source token address
    /// @param destToken Destination token address
    /// @param amount Payment amount
    /// @param minAmountOut Minimum acceptable output amount (slippage protection)
    function createPaymentWithSlippage(
        bytes calldata destChainId,
        bytes calldata receiver,
        address sourceToken,
        address destToken,
        uint256 amount,
        uint256 minAmountOut
    ) external payable returns (bytes32 paymentId);

    function executePayment(bytes32 paymentId) external payable;

    function createPaymentRequest(
        address receiver,
        address token,
        uint256 amount,
        string calldata description
    ) external returns (bytes32 requestId);

    function payRequest(bytes32 requestId) external;

    function processRefund(bytes32 paymentId) external;

    function getPayment(
        bytes32 paymentId
    ) external view returns (Payment memory);

    function isRequestExpired(bytes32 requestId) external view returns (bool);
    
    function retryMessage(bytes32 messageId) external;

    // ============ Phase-0 V2 (non-breaking) ============

    function createPaymentV2(PaymentRequestV2 calldata req) external payable returns (bytes32 paymentId);

    function createPaymentPrivateV2(
        PaymentRequestV2 calldata req,
        PrivateRouting calldata privacy
    ) external payable returns (bytes32 paymentId);

    function createPaymentV2DefaultBridge(PaymentRequestV2 calldata req) external payable returns (bytes32 paymentId);

    function quotePaymentCostV2(
        PaymentRequestV2 calldata req
    )
        external
        view
        returns (
            uint256 platformFee,
            uint256 bridgeFeeNative,
            uint256 totalSourceTokenRequired,
            uint8 bridgeType,
            bool bridgeQuoteOk,
            string memory bridgeQuoteReason
        );

    function previewApprovalV2(
        PaymentRequestV2 calldata req
    ) external view returns (address approvalToken, uint256 approvalAmount, uint256 requiredNativeFee);
}
