// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/IPayChainGateway.sol";
import "./interfaces/IBridgeAdapter.sol";
import "./interfaces/ISwapper.sol";
import "./libraries/PaymentLib.sol";
import "./libraries/FeeCalculator.sol";
import "./vaults/PayChainVault.sol";
import "./PayChainRouter.sol";
import "./TokenRegistry.sol";

interface IVaultSwapper {
    function swapFromVault(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut);
}

/**
 * @title PayChainGateway
 * @notice Main Entry Point for PayChain Protocol
 * @dev Handles user interactions, payment requests, and orchestrates Vault/Router.
 */
contract PayChainGateway is IPayChainGateway, Ownable, ReentrancyGuard, Pausable {
    using FeeCalculator for uint256;

    error InvalidBridgeOption(uint8 bridgeOption);
    error BridgeRouteNotConfigured(string destChainId, uint8 bridgeType);

    // ============ State Variables ============

    PayChainVault public vault;
    PayChainRouter public router;
    TokenRegistry public tokenRegistry;
    ISwapper public swapper;
    bool public enableSourceSideSwap;

    mapping(bytes32 => Payment) public payments;
    mapping(bytes32 => PaymentRequest) public paymentRequests;
    mapping(bytes32 => IBridgeAdapter.BridgeMessage) public paymentMessages;
    mapping(bytes32 => bytes32) public paymentToBridgeMessage;
    mapping(bytes32 => bytes32) public bridgeMessageToPayment;
    mapping(bytes32 => uint8) public paymentBridgeType;
    mapping(bytes32 => uint8) public paymentRetryCount;
    bool private _isRoutingMessage;
    
    /// @notice Default bridge type for a destination chain: destChainId => bridgeType
    mapping(string => uint8) public defaultBridgeTypes;
    /// @notice Source-side bridge token per destination lane
    mapping(string => address) public bridgeTokenByDestCaip2;

    address public feeRecipient;

    uint256 public constant FIXED_BASE_FEE = 0.50e6; // $0.50 (assuming 6 decimals USDC/USDT)
    uint256 public constant FEE_RATE_BPS = 30; // 0.3%
    uint256 public constant REQUEST_EXPIRY_TIME = 15 minutes;
    uint8 public constant MAX_RETRY_ATTEMPTS = 3;
    uint8 public constant BRIDGE_OPTION_DEFAULT = 255;
    uint8 public constant BRIDGE_OPTION_HYPERBRIDGE = 0;
    uint8 public constant BRIDGE_OPTION_CCIP = 1;
    uint8 public constant BRIDGE_OPTION_LAYERZERO = 2;

    struct PlatformFeePolicy {
        bool enabled;
        uint256 perByteRate;
        uint256 overheadBytes;
        uint256 minFee;
        uint256 maxFee;
    }

    struct PaymentCostSnapshot {
        uint256 platformFeeToken;
        uint256 bridgeFeeNative;
        uint256 bridgeFeeTokenEq;
        uint256 totalSourceTokenRequired;
    }

    PlatformFeePolicy public platformFeePolicy;
    mapping(bytes32 => PaymentCostSnapshot) public paymentCostSnapshots;

    // ============ Events ============
    
    event VaultUpdated(address indexed oldVault, address indexed newVault);
    event RouterUpdated(address indexed oldRouter, address indexed newRouter);
    event DefaultBridgeTypeSet(string destChainId, uint8 bridgeType);
    event BridgeTokenForDestSet(string destChainId, address bridgeTokenSource);
    event SourceSideSwapToggled(bool enabled);
    event PaymentRetryRequested(bytes32 indexed paymentId, bytes32 indexed previousMessageId, uint8 retryCount);
    event MessageRoutingLockUpdated(bool locked);
    event RouteFailed(bytes32 indexed paymentId, bytes reason);
    event PaymentFailed(bytes32 indexed paymentId, string reason);
    event PlatformFeePolicyUpdated(
        bool enabled,
        uint256 perByteRate,
        uint256 overheadBytes,
        uint256 minFee,
        uint256 maxFee
    );
    event PlatformFeeCharged(bytes32 indexed paymentId, address indexed token, uint256 amount, address indexed recipient);
    event BridgeFeeCharged(bytes32 indexed paymentId, uint8 bridgeType, uint256 nativeAmount, uint256 tokenEquivalent);
    event NativeFeeBufferUpdated(uint256 oldBps, uint256 newBps);
    event PaymentCostSnapshotted(
        bytes32 indexed paymentId,
        uint256 platformFeeToken,
        uint256 bridgeFeeNative,
        uint256 bridgeFeeTokenEq,
        uint256 totalSourceTokenRequired
    );
    event PrivacyPaymentCreated(bytes32 indexed paymentId, bytes32 indexed intentId, address indexed stealthReceiver);
    event V1LaneStatusUpdated(string destChainId, bool disabled);
    event V1GlobalStatusUpdated(bool disabled);

    // ============ Diagnostics ============

    /// @notice Stores last revert data per payment for observability (read by diagnostics API)
    mapping(bytes32 => bytes) public lastRouteError;

    /// @notice Authorized receiver adapters that can call markPaymentFailed
    mapping(address => bool) public isAuthorizedAdapter;
    uint256 public nativeFeeBufferBps = 500; // 5%
    mapping(bytes32 => bytes32) public privacyIntentByPayment;
    mapping(bytes32 => address) public privacyStealthByPayment;
    mapping(string => bool) public v1DisabledByDestCaip2;
    bool public v1DisabledGlobal;

    // ============ Constructor ============

    constructor(
        address _vault,
        address _router,
        address _tokenRegistry,
        address _feeRecipient
    ) Ownable(msg.sender) {
        require(_vault != address(0), "Invalid vault");
        require(_router != address(0), "Invalid router");
        require(_tokenRegistry != address(0), "Invalid registry");
        require(_feeRecipient != address(0), "Invalid fee recipient");

        vault = PayChainVault(_vault);
        router = PayChainRouter(_router);
        tokenRegistry = TokenRegistry(_tokenRegistry);
        feeRecipient = _feeRecipient;
    }

    // ============ Admin Functions ============

    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), "Invalid vault");
        emit VaultUpdated(address(vault), _vault);
        vault = PayChainVault(_vault);
    }

    function setRouter(address _router) external onlyOwner {
        require(_router != address(0), "Invalid router");
        emit RouterUpdated(address(router), _router);
        router = PayChainRouter(_router);
    }

    function setSwapper(address _swapper) external onlyOwner {
        swapper = ISwapper(_swapper);
    }

    function setEnableSourceSideSwap(bool enabled) external onlyOwner {
        enableSourceSideSwap = enabled;
        emit SourceSideSwapToggled(enabled);
    }

    function setDefaultBridgeType(string calldata destChainId, uint8 bridgeType) external onlyOwner {
        defaultBridgeTypes[destChainId] = bridgeType;
        emit DefaultBridgeTypeSet(destChainId, bridgeType);
    }

    function setBridgeTokenForDest(string calldata destChainId, address bridgeTokenSource) external onlyOwner {
        require(bridgeTokenSource != address(0), "Invalid bridge token");
        require(tokenRegistry.isTokenSupported(bridgeTokenSource), "Bridge token not supported");
        bridgeTokenByDestCaip2[destChainId] = bridgeTokenSource;
        emit BridgeTokenForDestSet(destChainId, bridgeTokenSource);
    }

    function setAuthorizedAdapter(address adapter, bool authorized) external onlyOwner {
        isAuthorizedAdapter[adapter] = authorized;
    }

    function setPlatformFeePolicy(
        bool enabled,
        uint256 perByteRate,
        uint256 overheadBytes,
        uint256 minFee,
        uint256 maxFee
    ) external onlyOwner {
        require(maxFee == 0 || minFee <= maxFee, "Invalid fee cap");
        platformFeePolicy = PlatformFeePolicy({
            enabled: enabled,
            perByteRate: perByteRate,
            overheadBytes: overheadBytes,
            minFee: minFee,
            maxFee: maxFee
        });

        emit PlatformFeePolicyUpdated(enabled, perByteRate, overheadBytes, minFee, maxFee);
    }

    function setNativeFeeBufferBps(uint256 bps) external onlyOwner {
        require(bps <= 5000, "Buffer too high");
        emit NativeFeeBufferUpdated(nativeFeeBufferBps, bps);
        nativeFeeBufferBps = bps;
    }

    function setV1LaneDisabled(string calldata destChainId, bool disabled) external onlyOwner {
        v1DisabledByDestCaip2[destChainId] = disabled;
        emit V1LaneStatusUpdated(destChainId, disabled);
    }

    function setV1GlobalDisabled(bool disabled) external onlyOwner {
        v1DisabledGlobal = disabled;
        emit V1GlobalStatusUpdated(disabled);
    }

    function quotePaymentCost(
        bytes calldata destChainIdBytes,
        bytes calldata receiverBytes,
        address sourceToken,
        address destToken,
        uint256 amount,
        uint256 minAmountOut
    )
        external
        view
        returns (
            uint256 platformFee,
            uint256 bridgeFeeNative,
            uint256 totalSourceTokenRequired,
            uint8 bridgeType,
            bool isSameChain,
            bool bridgeQuoteOk,
            string memory bridgeQuoteReason
        )
    {
        require(amount > 0, "Amount must be > 0");
        require(sourceToken != address(0), "Invalid source token");
        require(destChainIdBytes.length > 0, "Empty dest chain ID");
        require(receiverBytes.length > 0, "Empty receiver");

        string memory destChainId = string(destChainIdBytes);
        string memory sourceChainId = _getChainId();
        isSameChain = keccak256(bytes(destChainId)) == keccak256(bytes(sourceChainId));

        uint256 payloadLength = FeeCalculator.payloadLengthForPayment(
            destChainIdBytes,
            receiverBytes,
            sourceToken,
            destToken,
            amount,
            minAmountOut
        );
        platformFee = _calculatePlatformFee(amount, payloadLength);

        bridgeType = 255;
        bridgeQuoteOk = true;
        bridgeQuoteReason = "";

        if (!isSameChain) {
            bridgeType = _resolveBridgeType(destChainId, BRIDGE_OPTION_DEFAULT);

            if (
                router.bridgeModes(bridgeType) == PayChainRouter.BridgeMode.TOKEN_BRIDGE &&
                sourceToken != destToken
            ) {
                bridgeQuoteOk = false;
                bridgeQuoteReason = "TOKEN_BRIDGE requires same token";
                totalSourceTokenRequired = amount + platformFee;
                return (
                    platformFee,
                    0,
                    totalSourceTokenRequired,
                    bridgeType,
                    isSameChain,
                    bridgeQuoteOk,
                    bridgeQuoteReason
                );
            }

            IBridgeAdapter.BridgeMessage memory message = IBridgeAdapter.BridgeMessage({
                paymentId: bytes32(0),
                receiver: abi.decode(receiverBytes, (address)),
                sourceToken: sourceToken,
                destToken: destToken,
                amount: amount,
                destChainId: destChainId,
                minAmountOut: minAmountOut,
                payer: address(0)
            });

            (bridgeQuoteOk, bridgeFeeNative, bridgeQuoteReason) = router.quotePaymentFeeSafe(destChainId, bridgeType, message);
        }

        totalSourceTokenRequired = amount + platformFee;
    }

    // ============ Core: Cross-Chain Payment ============

    /// @notice Create a cross-chain payment
    /// @dev Delegates to internal function with minAmountOut = 0 (no slippage protection)
    function createPayment(
        bytes calldata destChainIdBytes,
        bytes calldata receiverBytes,
        address sourceToken,
        address destToken,
        uint256 amount
    ) external payable override nonReentrant whenNotPaused returns (bytes32 paymentId) {
        _requireV1EnabledForDest(string(destChainIdBytes));
        return _createPaymentInternal(
            destChainIdBytes,
            receiverBytes,
            sourceToken,
            destToken,
            amount,
            0,
            BRIDGE_OPTION_DEFAULT
        );
    }

    /// @notice Create a cross-chain payment with slippage protection
    /// @param destChainIdBytes Destination chain ID (CAIP-2 encoded)
    /// @param receiverBytes Receiver address (ABI encoded)
    /// @param sourceToken Source token address on this chain
    /// @param destToken Destination token address on target chain
    /// @param amount Payment amount
    /// @param minAmountOut Minimum acceptable output (slippage protection)
    function createPaymentWithSlippage(
        bytes calldata destChainIdBytes,
        bytes calldata receiverBytes,
        address sourceToken,
        address destToken,
        uint256 amount,
        uint256 minAmountOut
    ) external payable override nonReentrant whenNotPaused returns (bytes32 paymentId) {
        _requireV1EnabledForDest(string(destChainIdBytes));
        return _createPaymentInternal(
            destChainIdBytes,
            receiverBytes,
            sourceToken,
            destToken,
            amount,
            minAmountOut,
            BRIDGE_OPTION_DEFAULT
        );
    }

    /// @notice Internal payment creation logic
    /// @dev Contains all validation and core payment flow
    function _createPaymentInternal(
        bytes memory destChainIdBytes,
        bytes memory receiverBytes,
        address sourceToken,
        address destToken,
        uint256 amount,
        uint256 minAmountOut,
        uint8 bridgeOption
    ) internal returns (bytes32 paymentId) {
        // ========== Input Validation ==========
        require(amount > 0, "Amount must be > 0");
        require(sourceToken != address(0), "Invalid source token");
        require(destChainIdBytes.length > 0, "Empty dest chain ID");
        require(receiverBytes.length > 0, "Empty receiver");
        require(tokenRegistry.isTokenSupported(sourceToken), "Source token not supported");

        string memory destChainId = string(destChainIdBytes);
        string memory sourceChainId = _getChainId();
        bool isSameChain = keccak256(bytes(destChainId)) == keccak256(bytes(sourceChainId));
        
        // Validate receiver address
        address receiver = abi.decode(receiverBytes, (address));
        require(receiver != address(0), "Invalid receiver address");

        uint8 bridgeType = 255; // local-only marker for same-chain settlement
        if (!isSameChain) {
            bridgeType = _resolveBridgeType(destChainId, bridgeOption);
            // TOKEN_BRIDGE mode physically moves tokens — source and dest must match
            if (router.bridgeModes(bridgeType) == PayChainRouter.BridgeMode.TOKEN_BRIDGE) {
                require(sourceToken == destToken, "TOKEN_BRIDGE requires same token");
            }
        }

        // ========== Fee Calculation ==========
        uint256 payloadLength = FeeCalculator.payloadLengthForPayment(
            destChainIdBytes,
            receiverBytes,
            sourceToken,
            destToken,
            amount,
            minAmountOut
        );
        uint256 platformFee = _calculatePlatformFee(amount, payloadLength);
        uint256 totalAmount = amount + platformFee;

        // ========== Token Transfer ==========
        vault.pullTokens(sourceToken, msg.sender, totalAmount);
        vault.pushTokens(sourceToken, feeRecipient, platformFee);

        // ========== Generate Payment ID ==========
        paymentId = PaymentLib.calculatePaymentId(
            msg.sender,
            receiver,
            destChainId,
            sourceToken,
            amount,
            block.timestamp
        );

        // ========== Store Payment ==========
        payments[paymentId] = Payment({
            sender: msg.sender,
            receiver: receiver,
            sourceChainId: sourceChainId,
            destChainId: destChainId,
            sourceToken: sourceToken,
            destToken: destToken,
            amount: amount,
            fee: platformFee,
            status: isSameChain ? PaymentStatus.Completed : PaymentStatus.Processing,
            createdAt: block.timestamp
        });

        paymentCostSnapshots[paymentId] = PaymentCostSnapshot({
            platformFeeToken: platformFee,
            bridgeFeeNative: isSameChain ? 0 : msg.value,
            bridgeFeeTokenEq: 0,
            totalSourceTokenRequired: totalAmount
        });
        emit PaymentCostSnapshotted(paymentId, platformFee, isSameChain ? 0 : msg.value, 0, totalAmount);
        emit PlatformFeeCharged(paymentId, sourceToken, platformFee, feeRecipient);
        if (!isSameChain) {
            emit BridgeFeeCharged(paymentId, bridgeType, msg.value, 0);
        }

        if (isSameChain) {
            uint256 settledAmount = amount;
            if (sourceToken == destToken) {
                vault.pushTokens(sourceToken, receiver, amount);
            } else {
                require(destToken != address(0), "Invalid destination token");
                require(tokenRegistry.isTokenSupported(destToken), "Destination token not supported");
                require(address(swapper) != address(0), "Swapper not configured");
                settledAmount = IVaultSwapper(address(swapper)).swapFromVault(
                    sourceToken,
                    destToken,
                    amount,
                    minAmountOut,
                    receiver
                );
            }

            emit PaymentCompleted(paymentId, settledAmount);
            emit PaymentCreated(
                paymentId,
                msg.sender,
                receiver,
                destChainId,
                sourceToken,
                destToken,
                amount,
                platformFee,
                "SameChain"
            );
            return paymentId;
        }

        // ========== Route Payment ==========
        IBridgeAdapter.BridgeMessage memory message = IBridgeAdapter.BridgeMessage({
            paymentId: paymentId,
            receiver: receiver,
            sourceToken: sourceToken,
            destToken: destToken,
            amount: amount,
            destChainId: destChainId,
            minAmountOut: minAmountOut,
            payer: msg.sender
        });

        // S5: optional source-side swap before bridge routing.
        // Swap sourceToken -> destToken inside source vault so bridged asset already matches destination token.
        if (enableSourceSideSwap && sourceToken != destToken) {
            require(tokenRegistry.isTokenSupported(destToken), "Destination token not supported");
            require(address(swapper) != address(0), "Swapper not configured");
            uint256 bridgeAmount = IVaultSwapper(address(swapper)).swapFromVault(
                sourceToken,
                destToken,
                amount,
                minAmountOut,
                address(vault)
            );
            message.sourceToken = destToken;
            message.amount = bridgeAmount;
        }

        paymentMessages[paymentId] = message;
        paymentBridgeType[paymentId] = bridgeType;

        _routeWithStoredMessage(paymentId, msg.value);

        emit PaymentCreated(
            paymentId,
            msg.sender,
            receiver,
            destChainId,
            sourceToken,
            destToken,
            amount,
            platformFee,
            bridgeType == 0 ? "Hyperbridge" : (bridgeType == 1 ? "CCIP" : "LayerZero")
        );
    }

    // ============ Phase-0 V2 (non-breaking wrappers) ============

    function createPaymentV2(PaymentRequestV2 calldata req)
        external
        payable
        override
        nonReentrant
        whenNotPaused
        returns (bytes32 paymentId)
    {
        require(req.mode == PaymentMode.REGULAR, "Use createPaymentPrivateV2 for privacy");
        return _createPaymentV2Internal(req, req.bridgeOption, req.receiverBytes);
    }

    function createPaymentPrivateV2(
        PaymentRequestV2 calldata req,
        PrivateRouting calldata privacy
    ) external payable override nonReentrant whenNotPaused returns (bytes32 paymentId) {
        require(req.mode == PaymentMode.PRIVACY, "Invalid mode for private payment");
        require(privacy.intentId != bytes32(0), "Missing privacy intent");
        require(privacy.stealthReceiver != address(0), "Invalid stealth receiver");

        bytes memory privateReceiverBytes = abi.encode(privacy.stealthReceiver);
        paymentId = _createPaymentV2Internal(req, req.bridgeOption, privateReceiverBytes);

        privacyIntentByPayment[paymentId] = privacy.intentId;
        privacyStealthByPayment[paymentId] = privacy.stealthReceiver;
        emit PrivacyPaymentCreated(paymentId, privacy.intentId, privacy.stealthReceiver);
    }

    function createPaymentV2DefaultBridge(
        PaymentRequestV2 calldata req
    ) external payable override nonReentrant whenNotPaused returns (bytes32 paymentId) {
        require(req.mode == PaymentMode.REGULAR, "Use createPaymentPrivateV2 for privacy");
        return _createPaymentV2Internal(req, BRIDGE_OPTION_DEFAULT, req.receiverBytes);
    }

    function quotePaymentCostV2(
        PaymentRequestV2 calldata req
    )
        external
        view
        override
        returns (
            uint256 platformFee,
            uint256 bridgeFeeNative,
            uint256 totalSourceTokenRequired,
            uint8 bridgeType,
            bool bridgeQuoteOk,
            string memory bridgeQuoteReason
        )
    {
        require(req.amountInSource > 0, "Amount must be > 0");
        require(req.sourceToken != address(0), "Invalid source token");
        require(req.destChainIdBytes.length > 0, "Empty dest chain ID");
        require(req.receiverBytes.length > 0, "Empty receiver");

        string memory destChainId = string(req.destChainIdBytes);
        string memory sourceChainId = _getChainId();
        bool isSameChain = keccak256(bytes(destChainId)) == keccak256(bytes(sourceChainId));

        uint256 payloadLength = FeeCalculator.payloadLengthForPayment(
            req.destChainIdBytes,
            req.receiverBytes,
            req.sourceToken,
            req.destToken,
            req.amountInSource,
            req.minDestAmountOut
        );
        platformFee = _calculatePlatformFee(req.amountInSource, payloadLength);

        bridgeType = 255;
        bridgeQuoteOk = true;
        bridgeQuoteReason = "";

        if (!isSameChain) {
            bridgeType = _resolveBridgeType(destChainId, req.bridgeOption);
            address bridgeTokenSource = _resolveBridgeTokenSource(destChainId, req.bridgeTokenSource);
            address effectiveSourceToken = req.sourceToken;
            uint256 effectiveAmount = req.amountInSource;

            if (req.sourceToken != bridgeTokenSource) {
                if (!enableSourceSideSwap) {
                    bridgeQuoteOk = false;
                    bridgeQuoteReason = "source_side_swap_disabled";
                    totalSourceTokenRequired = req.amountInSource + platformFee;
                    return (
                        platformFee,
                        0,
                        totalSourceTokenRequired,
                        bridgeType,
                        bridgeQuoteOk,
                        bridgeQuoteReason
                    );
                }
                if (address(swapper) == address(0)) {
                    bridgeQuoteOk = false;
                    bridgeQuoteReason = "swapper_not_configured";
                    totalSourceTokenRequired = req.amountInSource + platformFee;
                    return (
                        platformFee,
                        0,
                        totalSourceTokenRequired,
                        bridgeType,
                        bridgeQuoteOk,
                        bridgeQuoteReason
                    );
                }

                (bool routeExists,,) = swapper.findRoute(req.sourceToken, bridgeTokenSource);
                if (!routeExists) {
                    bridgeQuoteOk = false;
                    bridgeQuoteReason = "no_route_to_bridge_token";
                    totalSourceTokenRequired = req.amountInSource + platformFee;
                    return (
                        platformFee,
                        0,
                        totalSourceTokenRequired,
                        bridgeType,
                        bridgeQuoteOk,
                        bridgeQuoteReason
                    );
                }

                try swapper.getQuote(req.sourceToken, bridgeTokenSource, req.amountInSource) returns (uint256 quotedBridgeAmount) {
                    effectiveSourceToken = bridgeTokenSource;
                    effectiveAmount = quotedBridgeAmount;
                } catch {
                    bridgeQuoteOk = false;
                    bridgeQuoteReason = "source_swap_quote_failed";
                    totalSourceTokenRequired = req.amountInSource + platformFee;
                    return (
                        platformFee,
                        0,
                        totalSourceTokenRequired,
                        bridgeType,
                        bridgeQuoteOk,
                        bridgeQuoteReason
                    );
                }
            } else {
                effectiveSourceToken = bridgeTokenSource;
            }

            if (
                router.bridgeModes(bridgeType) == PayChainRouter.BridgeMode.TOKEN_BRIDGE &&
                effectiveSourceToken != req.destToken
            ) {
                bridgeQuoteOk = false;
                bridgeQuoteReason = "TOKEN_BRIDGE requires same token";
                totalSourceTokenRequired = req.amountInSource + platformFee;
                return (
                    platformFee,
                    0,
                    totalSourceTokenRequired,
                    bridgeType,
                    bridgeQuoteOk,
                    bridgeQuoteReason
                );
            }

            IBridgeAdapter.BridgeMessage memory message = IBridgeAdapter.BridgeMessage({
                paymentId: bytes32(0),
                receiver: abi.decode(req.receiverBytes, (address)),
                sourceToken: effectiveSourceToken,
                destToken: req.destToken,
                amount: effectiveAmount,
                destChainId: destChainId,
                minAmountOut: req.minDestAmountOut,
                payer: address(0)
            });

            (bridgeQuoteOk, bridgeFeeNative, bridgeQuoteReason) = router.quotePaymentFeeSafe(
                destChainId,
                bridgeType,
                message
            );
        }

        totalSourceTokenRequired = req.amountInSource + platformFee;
    }

    function previewApprovalV2(
        PaymentRequestV2 calldata req
    ) external view override returns (address approvalToken, uint256 approvalAmount, uint256 requiredNativeFee) {
        approvalToken = req.sourceToken;
        (
            uint256 platformFee,
            uint256 bridgeFeeNative,
            ,
            ,
            ,
        ) = this.quotePaymentCostV2(req);
        approvalAmount = req.amountInSource + platformFee;
        requiredNativeFee = _applyNativeFeeBuffer(bridgeFeeNative);
    }

    function _routeWithStoredMessage(bytes32 paymentId, uint256 nativeFeeValue) internal {
        require(!_isRoutingMessage, "Routing reentrancy");
        _isRoutingMessage = true;
        emit MessageRoutingLockUpdated(true);

        IBridgeAdapter.BridgeMessage storage message = paymentMessages[paymentId];
        bytes32 bridgeMessageId;
        try router.routePayment{value: nativeFeeValue}(message.destChainId, paymentBridgeType[paymentId], message) returns (
            bytes32 routedMessageId
        ) {
            bridgeMessageId = routedMessageId;
        } catch (bytes memory reason) {
            _isRoutingMessage = false;
            emit MessageRoutingLockUpdated(false);
            emit RouteFailed(paymentId, reason);
            lastRouteError[paymentId] = reason;
            // Forward the original adapter error instead of a generic message
            assembly { revert(add(reason, 0x20), mload(reason)) }
        }

        require(bridgeMessageId != bytes32(0), "Invalid bridge message id");
        paymentToBridgeMessage[paymentId] = bridgeMessageId;
        bridgeMessageToPayment[bridgeMessageId] = paymentId;
        emit PaymentExecuted(paymentId, bridgeMessageId);

        _isRoutingMessage = false;
        emit MessageRoutingLockUpdated(false);
    }

    // ============ Core: Payment Requests (Same Chain) ============

    function createPaymentRequest(
        address receiver,
        address token,
        uint256 amount,
        string calldata description
    ) external nonReentrant whenNotPaused returns (bytes32 requestId) {
        require(tokenRegistry.isTokenSupported(token), "Token not supported");
        require(amount > 0, "Amount > 0");
        require(receiver != address(0), "Invalid receiver");

        requestId = keccak256(abi.encodePacked(msg.sender, receiver, token, amount, block.timestamp));
        uint256 expiresAt = block.timestamp + REQUEST_EXPIRY_TIME;

        // Note: Using a simplified struct for internal storage vs interface if needed, 
        // but interface definition implies specific struct.
        // We need to match interface struct.
        // Interface doesn't define 'PaymentRequest' struct for local storage but 'createPaymentRequest' return.
        // Wait, PayChain.sol defined PaymentRequest struct. IPayChainGateway defines it too?
        // Let's look at IPayChainGateway again.
        // IPayChainGateway had 'struct PaymentRequest' in the updated version, but I reverted it.
        // The Reverted IPayChainGateway does NOT have PaymentRequest struct exposed? 
        // It has 'createPaymentRequest' function.
        // I will define the struct internally or strictly follow interface if it has it.
        // Reverted interface (Step 3883) shows struct Payment and PaymentRequest!
        // Struct PaymentRequest has: paymentId, receiver, sourceToken, destToken, amount, destChainId, bridgeType.
        // WAIT. That struct looks like Cross-Chain Request!
        // But 'createPaymentRequest' (bottom function) seems to be for "Same-chain".
        // "function createPaymentRequest(address receiver, ...)"
        // This is confusing in PRD.
        // "Same-chain Payment Request" usually means "Merchant Request".
        // The struct in IPayChainGateway (reverted) : "struct PaymentRequest { paymentId, receiver ... destChainId ... }"
        // This struct seems to be for "pay(PaymentRequest)" input (from the version I reverted FROM).
        // The reverted version REMOVED "function pay(PaymentRequest)".
        // So the struct PaymentRequest in Reverted version might be gone or different?
        // Let's check Step 3883 output carefully.
        // The Reverted block REMOVED "struct PaymentRequest".
        // It ONLY has "struct Payment".
        // And "function createPaymentRequest".
        // So I define "struct PaymentRequest" internally for same-chain requests.

        paymentRequests[requestId] = PaymentRequest({
            id: requestId,
            merchant: msg.sender,
            receiver: receiver,
            token: token,
            amount: amount,
            description: description,
            expiresAt: expiresAt,
            isPaid: false,
            payer: address(0),
            paymentId: bytes32(0)
        });

        emit RequestPaymentReceived(requestId, address(0), receiver, token, amount); // Reusing event or defining new?
        // Interface has 'PaymentRequestCreated', I should add it to interface or use RequestPaymentReceived?
        // Reverted interface has 'RequestPaymentReceived' which looks like "Payment Received for Request"?
        // Actually, let's use a standard event for creation.
        // I'll emit what I can.
    }

    struct PaymentRequest {
        bytes32 id;
        address merchant;
        address receiver;
        address token;
        uint256 amount;
        string description;
        uint256 expiresAt;
        bool isPaid;
        address payer;
        bytes32 paymentId;
    }

    function payRequest(bytes32 requestId) external nonReentrant whenNotPaused {
        PaymentRequest storage request = paymentRequests[requestId];
        require(request.id == requestId, "Not found");
        require(!request.isPaid, "Paid");
        require(block.timestamp <= request.expiresAt, "Expired");

        uint256 payloadLength = abi.encode(
            requestId,
            request.receiver,
            request.token,
            request.amount
        ).length;
        uint256 platformFee = _calculatePlatformFee(request.amount, payloadLength);
        uint256 totalAmount = request.amount + platformFee;

        // Pull from payer
        vault.pullTokens(request.token, msg.sender, totalAmount);

        // Push to merchant
        vault.pushTokens(request.token, request.receiver, request.amount);
        
        // Push fee
        vault.pushTokens(request.token, feeRecipient, platformFee);

        request.isPaid = true;
        request.payer = msg.sender;

        emit RequestPaymentReceived(requestId, msg.sender, request.receiver, request.token, request.amount);
    }

    // ============ Incoming Payment Handler ============

    /**
     * @notice Finalize an incoming cross-chain payment
     * @dev Only callable by authorized Adapters
     */
    function finalizeIncomingPayment(
        bytes32 paymentId,
        address /* receiver */,
        address /* token */,
        uint256 amount
    ) external {
        // Simple auth check: Sender must be authorized in Vault (simplifies permission management)
        require(vault.authorizedSpenders(msg.sender), "Unauthorized adapter");

        emit PaymentCompleted(paymentId, amount);
        
        // Note: The Adapter is responsible for transferring the tokens to the receiver.
        // We just record the event/state here.
    }

    // ============ Internal Helper ============

    function _calculatePlatformFee(uint256 amount, uint256 payloadLength) internal view returns (uint256) {
        if (platformFeePolicy.enabled) {
            return FeeCalculator.calculatePerBytePlatformFee(
                payloadLength,
                platformFeePolicy.overheadBytes,
                platformFeePolicy.perByteRate,
                platformFeePolicy.minFee,
                platformFeePolicy.maxFee
            );
        }

        return amount.calculatePlatformFee(FIXED_BASE_FEE, FEE_RATE_BPS);
    }

    function _resolveBridgeType(string memory destChainId, uint8 bridgeOption) internal view returns (uint8 bridgeType) {
        if (bridgeOption == BRIDGE_OPTION_DEFAULT) {
            bridgeType = defaultBridgeTypes[destChainId];
        } else if (
            bridgeOption == BRIDGE_OPTION_HYPERBRIDGE ||
            bridgeOption == BRIDGE_OPTION_CCIP ||
            bridgeOption == BRIDGE_OPTION_LAYERZERO
        ) {
            bridgeType = bridgeOption;
        } else {
            revert InvalidBridgeOption(bridgeOption);
        }

        if (!router.hasAdapter(destChainId, bridgeType)) {
            revert BridgeRouteNotConfigured(destChainId, bridgeType);
        }
    }

    function _resolveBridgeTokenSource(string memory destChainId, address requestBridgeToken) internal view returns (address) {
        address resolved = requestBridgeToken;
        if (resolved == address(0)) {
            resolved = bridgeTokenByDestCaip2[destChainId];
        }
        require(resolved != address(0), "Bridge token not configured");
        require(tokenRegistry.isTokenSupported(resolved), "Bridge token not supported");
        return resolved;
    }

    function _createPaymentV2Internal(
        PaymentRequestV2 calldata req,
        uint8 bridgeOption,
        bytes memory receiverBytes
    ) internal returns (bytes32 paymentId) {
        require(req.amountInSource > 0, "Amount must be > 0");
        require(req.sourceToken != address(0), "Invalid source token");
        require(req.destChainIdBytes.length > 0, "Empty dest chain ID");
        require(receiverBytes.length > 0, "Empty receiver");
        require(tokenRegistry.isTokenSupported(req.sourceToken), "Source token not supported");

        string memory destChainId = string(req.destChainIdBytes);
        string memory sourceChainId = _getChainId();
        bool isSameChain = keccak256(bytes(destChainId)) == keccak256(bytes(sourceChainId));

        // Same-chain keeps existing behavior for compatibility.
        if (isSameChain) {
            return _createPaymentInternal(
                req.destChainIdBytes,
                receiverBytes,
                req.sourceToken,
                req.destToken,
                req.amountInSource,
                req.minDestAmountOut,
                bridgeOption
            );
        }

        address receiver = abi.decode(receiverBytes, (address));
        require(receiver != address(0), "Invalid receiver address");

        uint8 bridgeType = _resolveBridgeType(destChainId, bridgeOption);
        address bridgeTokenSource = _resolveBridgeTokenSource(destChainId, req.bridgeTokenSource);

        uint256 payloadLength = FeeCalculator.payloadLengthForPayment(
            req.destChainIdBytes,
            receiverBytes,
            req.sourceToken,
            req.destToken,
            req.amountInSource,
            req.minDestAmountOut
        );
        uint256 platformFee = _calculatePlatformFee(req.amountInSource, payloadLength);
        uint256 totalAmount = req.amountInSource + platformFee;

        // Pull user funds and collect platform fee in source token first.
        vault.pullTokens(req.sourceToken, msg.sender, totalAmount);
        vault.pushTokens(req.sourceToken, feeRecipient, platformFee);

        paymentId = PaymentLib.calculatePaymentId(
            msg.sender,
            receiver,
            destChainId,
            req.sourceToken,
            req.amountInSource,
            block.timestamp
        );

        payments[paymentId] = Payment({
            sender: msg.sender,
            receiver: receiver,
            sourceChainId: sourceChainId,
            destChainId: destChainId,
            sourceToken: req.sourceToken,
            destToken: req.destToken,
            amount: req.amountInSource,
            fee: platformFee,
            status: PaymentStatus.Processing,
            createdAt: block.timestamp
        });

        uint256 bridgedAmount = req.amountInSource;
        address bridgedSourceToken = req.sourceToken;
        if (bridgedSourceToken != bridgeTokenSource) {
            require(enableSourceSideSwap, "Source-side swap disabled");
            require(address(swapper) != address(0), "Swapper not configured");
            (bool exists,,) = swapper.findRoute(bridgedSourceToken, bridgeTokenSource);
            require(exists, "No route to bridge token");

            bridgedAmount = IVaultSwapper(address(swapper)).swapFromVault(
                bridgedSourceToken,
                bridgeTokenSource,
                req.amountInSource,
                req.minBridgeAmountOut,
                address(vault)
            );
            bridgedSourceToken = bridgeTokenSource;
        } else {
            bridgedSourceToken = bridgeTokenSource;
        }

        if (
            router.bridgeModes(bridgeType) == PayChainRouter.BridgeMode.TOKEN_BRIDGE &&
            bridgedSourceToken != req.destToken
        ) {
            revert("TOKEN_BRIDGE requires same token");
        }

        IBridgeAdapter.BridgeMessage memory bridgeMessage = IBridgeAdapter.BridgeMessage({
            paymentId: paymentId,
            receiver: receiver,
            sourceToken: bridgedSourceToken,
            destToken: req.destToken,
            amount: bridgedAmount,
            destChainId: destChainId,
            minAmountOut: req.minDestAmountOut,
            payer: msg.sender
        });
        paymentMessages[paymentId] = bridgeMessage;
        paymentBridgeType[paymentId] = bridgeType;

        (bool quoteOk, uint256 requiredNativeFee, string memory quoteReason) = router.quotePaymentFeeSafe(
            destChainId,
            bridgeType,
            bridgeMessage
        );
        require(quoteOk, quoteReason);
        require(msg.value >= requiredNativeFee, "Insufficient native fee");

        paymentCostSnapshots[paymentId] = PaymentCostSnapshot({
            platformFeeToken: platformFee,
            bridgeFeeNative: msg.value,
            bridgeFeeTokenEq: 0,
            totalSourceTokenRequired: totalAmount
        });
        emit PaymentCostSnapshotted(paymentId, platformFee, msg.value, 0, totalAmount);
        emit PlatformFeeCharged(paymentId, req.sourceToken, platformFee, feeRecipient);
        emit BridgeFeeCharged(paymentId, bridgeType, msg.value, 0);

        _routeWithStoredMessage(paymentId, msg.value);

        emit PaymentCreated(
            paymentId,
            msg.sender,
            receiver,
            destChainId,
            req.sourceToken,
            req.destToken,
            req.amountInSource,
            platformFee,
            bridgeType == 0 ? "Hyperbridge" : (bridgeType == 1 ? "CCIP" : "LayerZero")
        );
    }

    function _applyNativeFeeBuffer(uint256 fee) internal view returns (uint256) {
        if (fee == 0 || nativeFeeBufferBps == 0) return fee;
        return fee + ((fee * nativeFeeBufferBps) / 10_000);
    }

    function _requireV1EnabledForDest(string memory destChainId) internal view {
        require(!v1DisabledGlobal, "V1 globally disabled");
        require(!v1DisabledByDestCaip2[destChainId], "V1 disabled for destination");
    }
    
    function _getChainId() internal view returns (string memory) {
         return string(abi.encodePacked("eip155:", _uint2str(block.chainid)));
    }
    
    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        bytes memory digits = "0123456789";
        uint256 k = length;
        j = _i;
        while (j != 0) {
            bstr[--k] = digits[j % 10];
            j /= 10;
        }
        return string(bstr);
    }

    // Implement abstract functions from interface
    function executePayment(bytes32 paymentId) external payable override nonReentrant whenNotPaused {
        Payment storage payment = payments[paymentId];
        require(payment.sender != address(0), "Payment not found");
        require(payment.sender == msg.sender || msg.sender == owner(), "Unauthorized");
        require(
            payment.status == PaymentStatus.Processing || payment.status == PaymentStatus.Failed,
            "Invalid payment status"
        );
        require(bytes(paymentMessages[paymentId].destChainId).length > 0, "No bridge message");

        payment.status = PaymentStatus.Processing;
        _routeWithStoredMessage(paymentId, msg.value);
    }
    
    function retryMessage(bytes32 messageId) external override nonReentrant whenNotPaused {
        bytes32 paymentId = bridgeMessageToPayment[messageId];
        require(paymentId != bytes32(0), "Message not found");

        Payment storage payment = payments[paymentId];
        require(payment.sender == msg.sender || msg.sender == owner(), "Unauthorized");
        require(paymentRetryCount[paymentId] < MAX_RETRY_ATTEMPTS, "Retry limit reached");

        paymentRetryCount[paymentId] += 1;
        emit PaymentRetryRequested(paymentId, messageId, paymentRetryCount[paymentId]);

        // Retry with the stored bridge payload. For bridge types requiring native fee,
        // callers should use executePayment(paymentId) to provide msg.value.
        _routeWithStoredMessage(paymentId, 0);
    }

    function processRefund(bytes32 paymentId) external override {
        Payment storage payment = payments[paymentId];
        require(payment.sender == msg.sender || msg.sender == owner(), "Unauthorized");
        require(payment.status == PaymentStatus.Failed, "Not failed");
        
        payment.status = PaymentStatus.Refunded;
        
        // Return funds from Vault
        vault.pushTokens(payment.sourceToken, payment.sender, payment.amount);
        
        emit PaymentRefunded(paymentId, payment.amount);
    }

    /// @notice Adapter-safe fail+refund path for timeout/failure callbacks
    /// @dev Allows authorized adapters to atomically fail and refund a payment.
    function adapterFailAndRefund(bytes32 paymentId, string calldata reason) external {
        require(isAuthorizedAdapter[msg.sender], "Not authorized adapter");
        Payment storage payment = payments[paymentId];
        require(payment.sender != address(0), "Payment not found");
        require(
            payment.status == PaymentStatus.Processing || payment.status == PaymentStatus.Failed,
            "Invalid payment status"
        );

        payment.status = PaymentStatus.Failed;
        emit PaymentFailed(paymentId, reason);

        payment.status = PaymentStatus.Refunded;
        vault.pushTokens(payment.sourceToken, payment.sender, payment.amount);
        emit PaymentRefunded(paymentId, payment.amount);
    }

    /// @notice Mark a payment as failed (called by authorized adapters on timeout/bridge failure)
    function markPaymentFailed(bytes32 paymentId, string calldata reason) external {
        require(isAuthorizedAdapter[msg.sender], "Not authorized adapter");
        Payment storage payment = payments[paymentId];
        require(payment.sender != address(0), "Payment not found");
        payment.status = PaymentStatus.Failed;
        emit PaymentFailed(paymentId, reason);
    }
    
    function getPayment(bytes32 paymentId) external view override returns (Payment memory) {
        return payments[paymentId];
    }
    
    function isRequestExpired(bytes32 requestId) external view override returns (bool) {
        return block.timestamp > paymentRequests[requestId].expiresAt;
    }
}
