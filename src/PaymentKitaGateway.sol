// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/IPaymentKitaGateway.sol";
import "./interfaces/IBridgeAdapter.sol";
import "./interfaces/ISwapper.sol";
import "./interfaces/IGatewayValidatorModule.sol";
import "./interfaces/IGatewayQuoteModule.sol";
import "./interfaces/IGatewayExecutionModule.sol";
import "./interfaces/IGatewayPrivacyModule.sol";
import "./interfaces/IFeePolicyManager.sol";
import "./libraries/PaymentLib.sol";
import "./libraries/FeeCalculator.sol";
import "./vaults/PaymentKitaVault.sol";
import "./PaymentKitaRouter.sol";
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
 * @title PaymentKitaGateway
 * @notice Main Entry Point for PaymentKita Protocol
 * @dev Handles user interactions, payment requests, and orchestrates Vault/Router.
 */
contract PaymentKitaGateway is IPaymentKitaGateway, Ownable, ReentrancyGuard, Pausable {
    error InvalidBridgeOption(uint8 bridgeOption);
    error BridgeRouteNotConfigured(string destChainId, uint8 bridgeType);
    error RequestFlowDisabled();
    error QuoteModuleNotConfigured();
    error ExecutionModuleNotConfigured();
    error ValidatorModuleNotConfigured();
    error FeePolicyManagerNotConfigured();
    error InvalidVault();
    error InvalidRouter();
    error InvalidRegistry();
    error InvalidFeeRecipient();
    error InvalidValidatorModule();
    error InvalidQuoteModule();
    error InvalidExecutionModule();
    error InvalidPrivacyModule();
    error InvalidFeeManager();
    error InvalidBridgeToken();
    error BridgeTokenNotSupported();
    error InvalidFeeCap();
    error NativeFeeBufferTooHigh();
    error EmptyDestChainId();
    error OnlySameChain();
    error InvalidDestinationToken();
    error DestinationTokenNotSupported();
    error SwapperNotConfigured();
    error RegularModeRequired();
    error PrivacyModeRequired();
    error MissingPrivacyIntent();
    error InvalidStealthReceiver();
    error StealthReceiverMustDiffer();
    error RoutingReentrancy();
    error InvalidBridgeMessageId();
    error UnauthorizedAdapter();
    error PrivacyForwardAlreadyCompleted();
    error PrivacyPaymentNotFound();
    error MissingFinalReceiver();
    error InvalidForwardToken();
    error InvalidForwardAmount();
    error PrivacyModuleUnavailable();
    error BridgeTokenNotConfigured();
    error SourceSideSwapDisabled();
    error NoRouteToBridgeToken();
    error TokenBridgeRequiresSameToken();
    error PaymentNotFound();
    error UnauthorizedCaller();
    error InvalidPaymentStatus();
    error NoBridgeMessage();
    error MessageNotFound();
    error RetryLimitReached();
    error PaymentNotFailed();
    error NotAuthorizedAdapter();
    error PrivacyRecoveryUnauthorized();
    error PrivacyRetryNotAvailable();

    // ============ State Variables ============

    PaymentKitaVault public vault;
    PaymentKitaRouter public router;
    TokenRegistry public tokenRegistry;
    ISwapper public swapper;
    // Phase-1 modular facade pointers (non-breaking, optional wiring).
    address public validatorModule;
    address public quoteModule;
    address public executionModule;
    address public privacyModule;
    address public feePolicyManager;
    bool public enableSourceSideSwap;

    mapping(bytes32 => Payment) private payments;
    mapping(bytes32 => IBridgeAdapter.BridgeMessage) private paymentMessages;
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
    string public currentChainCaip2;

    uint256 public constant FIXED_BASE_FEE = 0.50e6; // $0.50 (assuming 6 decimals USDC/USDT)
    uint256 public constant FEE_RATE_BPS = 30; // 0.3%
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

    struct PaymentCostQuote {
        uint256 platformFee;
        uint256 bridgeFeeNative;
        uint256 totalSourceTokenRequired;
        uint8 bridgeType;
        bool bridgeQuoteOk;
        string bridgeQuoteReason;
    }

    PlatformFeePolicy public platformFeePolicy;
    mapping(bytes32 => PaymentCostSnapshot) private paymentCostSnapshots;

    // ============ Events ============
    
    event VaultUpdated(address indexed oldVault, address indexed newVault);
    event RouterUpdated(address indexed oldRouter, address indexed newRouter);
    event TokenRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
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
    event PrivacyPaymentCreated(
        bytes32 indexed paymentId,
        bytes32 indexed intentId,
        address indexed stealthReceiver,
        address finalReceiver
    );
    event PrivacyForwardRequested(
        bytes32 indexed paymentId,
        address indexed stealthReceiver,
        address indexed finalReceiver,
        address token,
        uint256 amount,
        bool sameChain,
        address actor
    );
    event PrivacyForwardCompleted(
        bytes32 indexed paymentId,
        address indexed stealthReceiver,
        address indexed finalReceiver,
        address token,
        uint256 amount,
        bool sameChain,
        address actor
    );
    event PrivacyForwardFailed(
        bytes32 indexed paymentId,
        uint8 retryCount,
        string reason,
        bool sameChain,
        address actor
    );
    event PrivacyForwardRetryRequested(
        bytes32 indexed paymentId,
        uint8 retryCount,
        address actor
    );
    event PrivacyEscrowClaimed(
        bytes32 indexed paymentId,
        address indexed finalReceiver,
        address indexed token,
        uint256 amount,
        address actor
    );
    event PrivacyEscrowRefunded(
        bytes32 indexed paymentId,
        address indexed sender,
        address indexed token,
        uint256 amount,
        address actor
    );
    event GatewayModulesUpdated(
        address indexed validatorModule,
        address indexed quoteModule,
        address indexed executionModule,
        address privacyModule
    );
    event FeePolicyManagerUpdated(address indexed oldManager, address indexed newManager);

    // ============ Diagnostics ============

    /// @notice Stores last revert data per payment for observability (read by diagnostics API)
    mapping(bytes32 => bytes) public lastRouteError;

    /// @notice Authorized receiver adapters that can call markPaymentFailed
    mapping(address => bool) public isAuthorizedAdapter;
    uint256 public nativeFeeBufferBps = 500; // 5%
    mapping(bytes32 => bytes32) public privacyIntentByPayment;
    mapping(bytes32 => address) public privacyStealthByPayment;
    mapping(bytes32 => address) public privacyFinalReceiverByPayment;
    mapping(bytes32 => bool) public privacyForwardCompleted;
    mapping(bytes32 => uint8) public privacyForwardRetryCount;
    mapping(bytes32 => address) public paymentSettledToken;
    mapping(bytes32 => uint256) public paymentSettledAmount;

    // ============ Constructor ============

    constructor(
        address _vault,
        address _router,
        address _tokenRegistry,
        address _feeRecipient
    ) Ownable(msg.sender) {
        if (_vault == address(0)) revert InvalidVault();
        if (_router == address(0)) revert InvalidRouter();
        if (_tokenRegistry == address(0)) revert InvalidRegistry();
        if (_feeRecipient == address(0)) revert InvalidFeeRecipient();

        vault = PaymentKitaVault(_vault);
        router = PaymentKitaRouter(_router);
        tokenRegistry = TokenRegistry(_tokenRegistry);
        feeRecipient = _feeRecipient;
        currentChainCaip2 = string(abi.encodePacked("eip155:", _uint2str(block.chainid)));
    }

    // ============ Admin Functions ============

    function setVault(address _vault) external onlyOwner {
        if (_vault == address(0)) revert InvalidVault();
        emit VaultUpdated(address(vault), _vault);
        vault = PaymentKitaVault(_vault);
    }

    function setRouter(address _router) external onlyOwner {
        if (_router == address(0)) revert InvalidRouter();
        emit RouterUpdated(address(router), _router);
        router = PaymentKitaRouter(_router);
    }

    function setTokenRegistry(address _tokenRegistry) external onlyOwner {
        if (_tokenRegistry == address(0)) revert InvalidRegistry();
        emit TokenRegistryUpdated(address(tokenRegistry), _tokenRegistry);
        tokenRegistry = TokenRegistry(_tokenRegistry);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0)) revert InvalidFeeRecipient();
        emit FeeRecipientUpdated(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    function setSwapper(address _swapper) external onlyOwner {
        swapper = ISwapper(_swapper);
    }

    function setGatewayModules(
        address _validatorModule,
        address _quoteModule,
        address _executionModule,
        address _privacyModule
    ) external onlyOwner {
        if (_validatorModule == address(0)) revert InvalidValidatorModule();
        if (_quoteModule == address(0)) revert InvalidQuoteModule();
        if (_executionModule == address(0)) revert InvalidExecutionModule();
        if (_privacyModule == address(0)) revert InvalidPrivacyModule();

        validatorModule = _validatorModule;
        quoteModule = _quoteModule;
        executionModule = _executionModule;
        privacyModule = _privacyModule;

        emit GatewayModulesUpdated(_validatorModule, _quoteModule, _executionModule, _privacyModule);
    }

    function setFeePolicyManager(address _manager) external onlyOwner {
        if (_manager == address(0)) revert InvalidFeeManager();
        emit FeePolicyManagerUpdated(feePolicyManager, _manager);
        feePolicyManager = _manager;
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
        if (bridgeTokenSource == address(0)) revert InvalidBridgeToken();
        if (!tokenRegistry.isTokenSupported(bridgeTokenSource)) revert BridgeTokenNotSupported();
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
        if (maxFee != 0 && minFee > maxFee) revert InvalidFeeCap();
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
        if (bps > 5000) revert NativeFeeBufferTooHigh();
        emit NativeFeeBufferUpdated(nativeFeeBufferBps, bps);
        nativeFeeBufferBps = bps;
    }

    // ============ Core: Cross-Chain Payment ============

    /// @notice Internal payment creation logic shared by V2 entrypoints
    function _createPaymentInternal(
        bytes memory destChainIdBytes,
        bytes memory receiverBytes,
        address sourceToken,
        address destToken,
        uint256 amount,
        uint256 minAmountOut,
        uint8 bridgeOption
    ) internal returns (bytes32 paymentId) {
        if (destChainIdBytes.length == 0) revert EmptyDestChainId();
        bridgeOption; // same-chain path ignores bridge option by design

        string memory destChainId = string(destChainIdBytes);
        string memory sourceChainId = currentChainCaip2;
        if (keccak256(bytes(destChainId)) != keccak256(bytes(sourceChainId))) revert OnlySameChain();

        address receiver = _validateCreateAndDecodeReceiver(
            receiverBytes,
            sourceToken,
            destToken,
            amount,
            false
        );

        uint256 payloadLength = FeeCalculator.payloadLengthForPayment(
            destChainIdBytes,
            receiverBytes,
            sourceToken,
            destToken,
            amount,
            minAmountOut
        );
        uint256 platformFee = _calculatePlatformFeeByPolicy(
            sourceChainId,
            destChainId,
            sourceToken,
            destToken,
            amount,
            payloadLength,
            0,
            0
        );
        uint256 totalAmount = amount + platformFee;

        vault.pullTokens(sourceToken, msg.sender, totalAmount);
        vault.pushTokens(sourceToken, feeRecipient, platformFee);

        paymentId = PaymentLib.calculatePaymentId(
            msg.sender,
            receiver,
            destChainId,
            sourceToken,
            amount,
            block.timestamp
        );

        payments[paymentId] = Payment({
            sender: msg.sender,
            receiver: receiver,
            sourceChainId: sourceChainId,
            destChainId: destChainId,
            sourceToken: sourceToken,
            destToken: destToken,
            amount: amount,
            fee: platformFee,
            status: PaymentStatus.Completed,
            createdAt: block.timestamp
        });

        paymentCostSnapshots[paymentId] = PaymentCostSnapshot({
            platformFeeToken: platformFee,
            bridgeFeeNative: 0,
            bridgeFeeTokenEq: 0,
            totalSourceTokenRequired: totalAmount
        });
        emit PaymentCostSnapshotted(paymentId, platformFee, 0, 0, totalAmount);
        emit PlatformFeeCharged(paymentId, sourceToken, platformFee, feeRecipient);
        uint256 settledAmount = amount;
        if (sourceToken == destToken) {
            vault.pushTokens(sourceToken, receiver, amount);
        } else {
            if (destToken == address(0)) revert InvalidDestinationToken();
            if (!tokenRegistry.isTokenSupported(destToken)) revert DestinationTokenNotSupported();
            if (address(swapper) == address(0)) revert SwapperNotConfigured();
            settledAmount = IVaultSwapper(address(swapper)).swapFromVault(
                sourceToken,
                destToken,
                amount,
                minAmountOut,
                receiver
            );
        }
        paymentSettledToken[paymentId] = sourceToken == destToken ? sourceToken : destToken;
        paymentSettledAmount[paymentId] = settledAmount;

        emit PaymentCompleted(paymentId, settledAmount);
        if (executionModule != address(0)) {
            IGatewayExecutionModule(executionModule).onSameChainSettled(
                paymentId,
                receiver,
                sourceToken == destToken ? sourceToken : destToken,
                settledAmount
            );
        }
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
    }

    // ============ Phase-0 V2 (non-breaking wrappers) ============

    function createPayment(PaymentRequestV2 calldata req)
        external
        payable
        override
        nonReentrant
        whenNotPaused
        returns (bytes32 paymentId)
    {
        if (req.mode != PaymentMode.REGULAR) revert RegularModeRequired();
        return _createPaymentV2Internal(req, req.bridgeOption, req.receiverBytes);
    }

    function createPaymentPrivate(
        PaymentRequestV2 calldata req,
        PrivateRouting calldata privacy
    ) external payable override nonReentrant whenNotPaused returns (bytes32 paymentId) {
        if (req.mode != PaymentMode.PRIVACY) revert PrivacyModeRequired();
        if (privacy.intentId == bytes32(0)) revert MissingPrivacyIntent();
        if (privacy.stealthReceiver == address(0)) revert InvalidStealthReceiver();

        address finalReceiver = _validateCreateAndDecodeReceiver(
            req.receiverBytes,
            req.sourceToken,
            req.destToken,
            req.amountInSource,
            false
        );
        if (privacy.stealthReceiver == finalReceiver) revert StealthReceiverMustDiffer();

        bytes memory privateReceiverBytes = abi.encode(privacy.stealthReceiver);
        paymentId = _createPaymentV2Internal(req, req.bridgeOption, privateReceiverBytes);

        privacyIntentByPayment[paymentId] = privacy.intentId;
        privacyStealthByPayment[paymentId] = privacy.stealthReceiver;
        privacyFinalReceiverByPayment[paymentId] = finalReceiver;
        privacyForwardCompleted[paymentId] = false;

        if (privacyModule != address(0)) {
            IGatewayPrivacyModule(privacyModule).recordPrivacyIntent(
                paymentId,
                privacy.intentId,
                privacy.stealthReceiver,
                msg.sender
            );
        }
        emit PrivacyPaymentCreated(paymentId, privacy.intentId, privacy.stealthReceiver, finalReceiver);

        bool sameChain = keccak256(req.destChainIdBytes) == keccak256(bytes(currentChainCaip2));
        if (sameChain) {
            _finalizeSameChainPrivacyForwardAtomic(paymentId);
        }
    }

    function createPaymentDefaultBridge(
        PaymentRequestV2 calldata req
    ) external payable override nonReentrant whenNotPaused returns (bytes32 paymentId) {
        if (req.mode != PaymentMode.REGULAR) revert RegularModeRequired();
        return _createPaymentV2Internal(req, BRIDGE_OPTION_DEFAULT, req.receiverBytes);
    }

    function quotePaymentCost(
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
        PaymentRequestV2 memory reqMem = req;
        PaymentCostQuote memory quote = _quotePaymentCostInternal(reqMem);
        platformFee = quote.platformFee;
        bridgeFeeNative = quote.bridgeFeeNative;
        totalSourceTokenRequired = quote.totalSourceTokenRequired;
        bridgeType = quote.bridgeType;
        bridgeQuoteOk = quote.bridgeQuoteOk;
        bridgeQuoteReason = quote.bridgeQuoteReason;
    }

    function previewApproval(
        PaymentRequestV2 calldata req
    ) external view override returns (address approvalToken, uint256 approvalAmount, uint256 requiredNativeFee) {
        approvalToken = req.sourceToken;
        PaymentRequestV2 memory reqMem = req;
        PaymentCostQuote memory quote = _quotePaymentCostInternal(reqMem);
        approvalAmount = quote.totalSourceTokenRequired;
        requiredNativeFee = quote.bridgeQuoteOk ? _applyNativeFeeBuffer(quote.bridgeFeeNative) : 0;
    }

    function _routeWithStoredMessage(bytes32 paymentId, uint256 nativeFeeValue) internal {
        if (_isRoutingMessage) revert RoutingReentrancy();
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

        if (bridgeMessageId == bytes32(0)) revert InvalidBridgeMessageId();
        paymentToBridgeMessage[paymentId] = bridgeMessageId;
        bridgeMessageToPayment[bridgeMessageId] = paymentId;
        emit PaymentExecuted(paymentId, bridgeMessageId);

        _isRoutingMessage = false;
        emit MessageRoutingLockUpdated(false);
    }

    // ============ Incoming Payment Handler ============

    /**
     * @notice Finalize an incoming cross-chain payment
     * @dev Only callable by authorized Adapters
     */
    function finalizeIncomingPayment(
        bytes32 paymentId,
        address /* receiver */,
        address token,
        uint256 amount
    ) external {
        // Simple auth check: Sender must be authorized in Vault (simplifies permission management)
        if (!vault.authorizedSpenders(msg.sender)) revert UnauthorizedAdapter();

        emit PaymentCompleted(paymentId, amount);
        if (executionModule != address(0)) {
            IGatewayExecutionModule(executionModule).onIncomingFinalized(paymentId, amount);
        }
        paymentSettledToken[paymentId] = token;
        paymentSettledAmount[paymentId] = amount;
        
        // Note: The Adapter is responsible for transferring the tokens to the receiver.
        // We just record the event/state here.
    }

    function finalizePrivacyForward(bytes32 paymentId, address token, uint256 amount) external override {
        if (!vault.authorizedSpenders(msg.sender)) revert UnauthorizedAdapter();
        if (privacyForwardCompleted[paymentId]) revert PrivacyForwardAlreadyCompleted();

        address stealthReceiver = privacyStealthByPayment[paymentId];
        address finalReceiver = privacyFinalReceiverByPayment[paymentId];
        if (stealthReceiver == address(0)) revert PrivacyPaymentNotFound();
        if (finalReceiver == address(0)) revert MissingFinalReceiver();
        if (stealthReceiver == finalReceiver) revert StealthReceiverMustDiffer();
        if (token == address(0)) revert InvalidForwardToken();
        if (amount == 0) revert InvalidForwardAmount();
        if (privacyModule == address(0)) revert PrivacyModuleUnavailable();

        bool sameChain = _isSameChainPayment(paymentId);
        _forwardFromStealth(paymentId, stealthReceiver, finalReceiver, token, amount, sameChain, msg.sender);

        privacyForwardCompleted[paymentId] = true;
        paymentSettledToken[paymentId] = token;
        paymentSettledAmount[paymentId] = amount;

        emit PrivacyForwardCompleted(paymentId, stealthReceiver, finalReceiver, token, amount, sameChain, msg.sender);
    }

    function reportPrivacyForwardFailure(bytes32 paymentId, string calldata reason) external override {
        if (!vault.authorizedSpenders(msg.sender)) revert UnauthorizedAdapter();
        if (privacyForwardCompleted[paymentId]) revert PrivacyForwardAlreadyCompleted();
        if (privacyStealthByPayment[paymentId] == address(0)) revert PrivacyPaymentNotFound();
        _recordPrivacyForwardFailure(paymentId, reason, _isSameChainPayment(paymentId), msg.sender);
    }

    function retryPrivacyForward(bytes32 paymentId) external override nonReentrant whenNotPaused {
        if (!_canActOnPrivacyRecovery(paymentId, msg.sender)) revert PrivacyRecoveryUnauthorized();
        if (privacyForwardCompleted[paymentId]) revert PrivacyForwardAlreadyCompleted();
        if (privacyStealthByPayment[paymentId] == address(0)) revert PrivacyPaymentNotFound();
        if (privacyForwardRetryCount[paymentId] == 0) revert PrivacyRetryNotAvailable();

        address token = paymentSettledToken[paymentId];
        uint256 amount = paymentSettledAmount[paymentId];
        if (token == address(0)) revert InvalidForwardToken();
        if (amount == 0) revert InvalidForwardAmount();

        emit PrivacyForwardRetryRequested(paymentId, privacyForwardRetryCount[paymentId], msg.sender);

        try this.finalizePrivacyForward(paymentId, token, amount) {
            return;
        } catch {
            _recordPrivacyForwardFailure(paymentId, "PRIVACY_FORWARD_RETRY_FAILED", _isSameChainPayment(paymentId), msg.sender);
        }
    }

    function claimPrivacyEscrow(bytes32 paymentId) external override nonReentrant whenNotPaused {
        if (privacyForwardCompleted[paymentId]) revert PrivacyForwardAlreadyCompleted();

        address stealthReceiver = privacyStealthByPayment[paymentId];
        if (stealthReceiver == address(0)) revert PrivacyPaymentNotFound();

        address finalReceiver = privacyFinalReceiverByPayment[paymentId];
        if (finalReceiver == address(0)) revert MissingFinalReceiver();
        if (msg.sender != finalReceiver) revert PrivacyRecoveryUnauthorized();

        address token = paymentSettledToken[paymentId];
        uint256 amount = paymentSettledAmount[paymentId];
        if (token == address(0)) revert InvalidForwardToken();
        if (amount == 0) revert InvalidForwardAmount();

        bool sameChain = _isSameChainPayment(paymentId);
        _forwardFromStealth(paymentId, stealthReceiver, finalReceiver, token, amount, sameChain, msg.sender);

        privacyForwardCompleted[paymentId] = true;
        paymentSettledToken[paymentId] = token;
        paymentSettledAmount[paymentId] = amount;

        emit PrivacyForwardCompleted(paymentId, stealthReceiver, finalReceiver, token, amount, sameChain, msg.sender);
        emit PrivacyEscrowClaimed(paymentId, finalReceiver, token, amount, msg.sender);
    }

    function refundPrivacyEscrow(bytes32 paymentId) external override nonReentrant whenNotPaused {
        if (privacyForwardCompleted[paymentId]) revert PrivacyForwardAlreadyCompleted();

        Payment storage payment = payments[paymentId];
        if (payment.sender == address(0)) revert PrivacyPaymentNotFound();
        if (!(msg.sender == payment.sender || msg.sender == owner())) revert PrivacyRecoveryUnauthorized();

        address stealthReceiver = privacyStealthByPayment[paymentId];
        if (stealthReceiver == address(0)) revert PrivacyPaymentNotFound();

        address token = paymentSettledToken[paymentId];
        uint256 amount = paymentSettledAmount[paymentId];
        if (token == address(0)) revert InvalidForwardToken();
        if (amount == 0) revert InvalidForwardAmount();

        bool sameChain = _isSameChainPayment(paymentId);
        _forwardFromStealth(paymentId, stealthReceiver, payment.sender, token, amount, sameChain, msg.sender);

        privacyForwardCompleted[paymentId] = true;
        paymentSettledToken[paymentId] = token;
        paymentSettledAmount[paymentId] = amount;

        emit PrivacyEscrowRefunded(paymentId, payment.sender, token, amount, msg.sender);
    }

    // ============ Internal Helper ============

    function _calculatePlatformFeeByPolicy(
        string memory sourceChainId,
        string memory destChainId,
        address sourceToken,
        address destToken,
        uint256 amount,
        uint256 payloadLength,
        uint256 bridgeFeeNative,
        uint256 swapImpactBps
    ) internal view returns (uint256) {
        if (feePolicyManager == address(0)) revert FeePolicyManagerNotConfigured();
        uint8 tokenDecimals = _getTokenDecimals(sourceToken);
        uint256 scaledFixedBaseFee = FeeCalculator.scaleFeeByDecimals(FIXED_BASE_FEE, tokenDecimals);
        return
            IFeePolicyManager(feePolicyManager).computePlatformFee(
                bytes(sourceChainId),
                bytes(destChainId),
                sourceToken,
                destToken,
                amount,
                bridgeFeeNative,
                swapImpactBps,
                platformFeePolicy.enabled,
                payloadLength,
                platformFeePolicy.overheadBytes,
                platformFeePolicy.perByteRate,
                platformFeePolicy.minFee,
                platformFeePolicy.maxFee,
                scaledFixedBaseFee,
                FEE_RATE_BPS
            );
    }

    function _validateCreateAndDecodeReceiver(
        bytes memory receiverBytes,
        address sourceToken,
        address destToken,
        uint256 amount,
        bool requireDestTokenSupported
    ) internal view returns (address receiver) {
        if (validatorModule == address(0)) revert ValidatorModuleNotConfigured();
        return
            IGatewayValidatorModule(validatorModule).validateCreate(
                address(tokenRegistry),
                receiverBytes,
                sourceToken,
                destToken,
                amount,
                true,
                requireDestTokenSupported
            );
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
        if (resolved == address(0)) revert BridgeTokenNotConfigured();
        if (!tokenRegistry.isTokenSupported(resolved)) revert BridgeTokenNotSupported();
        return resolved;
    }

    function _tryResolveBridgeType(
        string memory destChainId,
        uint8 bridgeOption
    ) internal view returns (bool ok, uint8 bridgeType, string memory reason) {
        if (bridgeOption == BRIDGE_OPTION_DEFAULT) {
            bridgeType = defaultBridgeTypes[destChainId];
        } else if (
            bridgeOption == BRIDGE_OPTION_HYPERBRIDGE ||
            bridgeOption == BRIDGE_OPTION_CCIP ||
            bridgeOption == BRIDGE_OPTION_LAYERZERO
        ) {
            bridgeType = bridgeOption;
        } else {
            return (false, 255, "invalid_bridge_option");
        }

        if (!router.hasAdapter(destChainId, bridgeType)) {
            return (false, bridgeType, "bridge_route_not_configured");
        }
        return (true, bridgeType, "");
    }

    function _tryResolveBridgeTokenSource(
        string memory destChainId,
        address requestBridgeToken
    ) internal view returns (bool ok, address resolved, string memory reason) {
        resolved = requestBridgeToken;
        if (resolved == address(0)) {
            resolved = bridgeTokenByDestCaip2[destChainId];
        }
        if (resolved == address(0)) {
            return (false, address(0), "bridge_token_not_configured");
        }
        if (!tokenRegistry.isTokenSupported(resolved)) {
            return (false, address(0), "bridge_token_not_supported");
        }
        return (true, resolved, "");
    }

    function _quotePaymentCostInternal(
        PaymentRequestV2 memory req
    ) internal view returns (PaymentCostQuote memory q) {
        q.bridgeType = 255;

        if (req.amountInSource == 0) {
            q.bridgeQuoteReason = "amount_must_be_gt_zero";
            return q;
        }
        if (req.sourceToken == address(0)) {
            q.bridgeQuoteReason = "invalid_source_token";
            return q;
        }
        if (req.destChainIdBytes.length == 0) {
            q.bridgeQuoteReason = "empty_dest_chain_id";
            return q;
        }
        if (req.receiverBytes.length == 0) {
            q.bridgeQuoteReason = "empty_receiver";
            return q;
        }

        string memory destChainId = string(req.destChainIdBytes);
        string memory sourceChainId = currentChainCaip2;
        bool isSameChain = keccak256(bytes(destChainId)) == keccak256(bytes(sourceChainId));

        uint256 payloadLength = FeeCalculator.payloadLengthForPayment(
            req.destChainIdBytes,
            req.receiverBytes,
            req.sourceToken,
            req.destToken,
            req.amountInSource,
            req.minDestAmountOut
        );
        q.platformFee = _calculatePlatformFeeByPolicy(
            sourceChainId,
            destChainId,
            req.sourceToken,
            req.destToken,
            req.amountInSource,
            payloadLength,
            0,
            0
        );
        q.totalSourceTokenRequired = req.amountInSource + q.platformFee;

        if (isSameChain) {
            q.bridgeQuoteOk = true;
            q.bridgeQuoteReason = "";
            return q;
        }

        (bool bridgeTypeOk, uint8 resolvedBridgeType, string memory bridgeTypeReason) = _tryResolveBridgeType(
            destChainId,
            req.bridgeOption
        );
        if (!bridgeTypeOk) {
            q.bridgeType = resolvedBridgeType;
            q.bridgeQuoteReason = bridgeTypeReason;
            return q;
        }
        q.bridgeType = resolvedBridgeType;

        (bool bridgeTokenOk, address bridgeTokenSource, string memory bridgeTokenReason) = _tryResolveBridgeTokenSource(
            destChainId,
            req.bridgeTokenSource
        );
        if (!bridgeTokenOk) {
            q.bridgeQuoteReason = bridgeTokenReason;
            return q;
        }

        if (quoteModule == address(0)) {
            q.bridgeQuoteReason = "quote_module_not_configured";
            return q;
        }

        (q.bridgeQuoteOk, q.bridgeFeeNative, q.bridgeQuoteReason) = IGatewayQuoteModule(quoteModule).quoteBridgeForV2(
            address(router),
            address(swapper),
            enableSourceSideSwap,
            destChainId,
            req.receiverBytes,
            req.sourceToken,
            req.destToken,
            req.amountInSource,
            req.minDestAmountOut,
            q.bridgeType,
            bridgeTokenSource
        );
    }

    function _createPaymentV2Internal(
        PaymentRequestV2 calldata req,
        uint8 bridgeOption,
        bytes memory receiverBytes
    ) internal returns (bytes32 paymentId) {
        if (req.destChainIdBytes.length == 0) revert EmptyDestChainId();

        string memory destChainId = string(req.destChainIdBytes);
        string memory sourceChainId = currentChainCaip2;
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

        address receiver = _validateCreateAndDecodeReceiver(
            receiverBytes,
            req.sourceToken,
            req.destToken,
            req.amountInSource,
            false
        );

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
        uint256 platformFee = _calculatePlatformFeeByPolicy(
            sourceChainId,
            destChainId,
            req.sourceToken,
            req.destToken,
            req.amountInSource,
            payloadLength,
            0,
            0
        );
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
            if (!enableSourceSideSwap) revert SourceSideSwapDisabled();
            if (address(swapper) == address(0)) revert SwapperNotConfigured();
            (bool exists,,) = swapper.findRoute(bridgedSourceToken, bridgeTokenSource);
            if (!exists) revert NoRouteToBridgeToken();

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
            router.bridgeModes(bridgeType) == PaymentKitaRouter.BridgeMode.TOKEN_BRIDGE &&
            bridgedSourceToken != req.destToken
        ) {
            revert TokenBridgeRequiresSameToken();
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

        if (quoteModule == address(0)) revert QuoteModuleNotConfigured();
        (bool quoteOk, uint256 requiredNativeFee, string memory quoteReason) = IGatewayQuoteModule(quoteModule)
            .quotePaymentFeeSafe(address(router), destChainId, bridgeType, bridgeMessage);
        require(quoteOk, quoteReason);
        if (executionModule == address(0)) revert ExecutionModuleNotConfigured();
        IGatewayExecutionModule(executionModule).beforeRoute(
            paymentId,
            destChainId,
            bridgeType,
            msg.value,
            requiredNativeFee
        );

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

    function _isSameChainPayment(bytes32 paymentId) internal view returns (bool) {
        Payment storage payment = payments[paymentId];
        if (payment.sender == address(0)) return false;
        return keccak256(bytes(payment.sourceChainId)) == keccak256(bytes(payment.destChainId));
    }

    function _canActOnPrivacyRecovery(bytes32 paymentId, address actor) internal view returns (bool) {
        Payment storage payment = payments[paymentId];
        if (payment.sender == address(0)) return false;
        return actor == payment.sender || actor == owner() || vault.authorizedSpenders(actor);
    }

    function _forwardFromStealth(
        bytes32 paymentId,
        address stealthReceiver,
        address finalReceiver,
        address token,
        uint256 amount,
        bool sameChain,
        address actor
    ) internal {
        emit PrivacyForwardRequested(paymentId, stealthReceiver, finalReceiver, token, amount, sameChain, actor);

        IGatewayPrivacyModule(privacyModule).forwardFromStealth(
            paymentId,
            stealthReceiver,
            finalReceiver,
            token,
            amount,
            actor,
            sameChain
        );
    }

    function _recordPrivacyForwardFailure(
        bytes32 paymentId,
        string memory reason,
        bool sameChain,
        address actor
    ) internal {
        unchecked {
            privacyForwardRetryCount[paymentId] += 1;
        }
        emit PrivacyForwardFailed(paymentId, privacyForwardRetryCount[paymentId], reason, sameChain, actor);
    }

    function _finalizeSameChainPrivacyForwardAtomic(bytes32 paymentId) internal {
        address settledToken = paymentSettledToken[paymentId];
        uint256 settledAmount = paymentSettledAmount[paymentId];
        if (settledToken == address(0)) revert InvalidForwardToken();
        if (settledAmount == 0) revert InvalidForwardAmount();

        // Atomic same-chain behavior: forward failure reverts the full createPaymentPrivate tx.
        this.finalizePrivacyForward(paymentId, settledToken, settledAmount);
    }

    function _getTokenDecimals(address token) internal view returns (uint8) {
        uint8 regDec = tokenRegistry.tokenDecimals(token);
        if (regDec > 0) return regDec;
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSignature("decimals()"));
        if (ok && data.length >= 32) {
            uint256 decRaw = abi.decode(data, (uint256));
            if (decRaw > 0 && decRaw <= type(uint8).max) {
                // forge-lint: disable-next-line(unsafe-typecast)
                return uint8(decRaw);
            }
        }
        return 6;
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
        if (payment.sender == address(0)) revert PaymentNotFound();
        if (!(payment.sender == msg.sender || msg.sender == owner())) revert UnauthorizedCaller();
        if (!(payment.status == PaymentStatus.Processing || payment.status == PaymentStatus.Failed)) revert InvalidPaymentStatus();
        if (bytes(paymentMessages[paymentId].destChainId).length == 0) revert NoBridgeMessage();

        payment.status = PaymentStatus.Processing;
        _routeWithStoredMessage(paymentId, msg.value);
    }
    
    function retryMessage(bytes32 messageId) external override nonReentrant whenNotPaused {
        bytes32 paymentId = bridgeMessageToPayment[messageId];
        if (paymentId == bytes32(0)) revert MessageNotFound();

        Payment storage payment = payments[paymentId];
        if (!(payment.sender == msg.sender || msg.sender == owner())) revert UnauthorizedCaller();
        if (paymentRetryCount[paymentId] >= MAX_RETRY_ATTEMPTS) revert RetryLimitReached();

        paymentRetryCount[paymentId] += 1;
        emit PaymentRetryRequested(paymentId, messageId, paymentRetryCount[paymentId]);

        // Retry with the stored bridge payload. For bridge types requiring native fee,
        // callers should use executePayment(paymentId) to provide msg.value.
        _routeWithStoredMessage(paymentId, 0);
    }

    function processRefund(bytes32 paymentId) external override {
        Payment storage payment = payments[paymentId];
        if (!(payment.sender == msg.sender || msg.sender == owner())) revert UnauthorizedCaller();
        if (payment.status != PaymentStatus.Failed) revert PaymentNotFailed();
        
        payment.status = PaymentStatus.Refunded;
        
        // Return funds from Vault
        vault.pushTokens(payment.sourceToken, payment.sender, payment.amount);
        
        emit PaymentRefunded(paymentId, payment.amount);
    }

    /// @notice Adapter-safe fail+refund path for timeout/failure callbacks
    /// @dev Allows authorized adapters to atomically fail and refund a payment.
    function adapterFailAndRefund(bytes32 paymentId, string calldata reason) external {
        if (!isAuthorizedAdapter[msg.sender]) revert NotAuthorizedAdapter();
        Payment storage payment = payments[paymentId];
        if (payment.sender == address(0)) revert PaymentNotFound();
        if (!(payment.status == PaymentStatus.Processing || payment.status == PaymentStatus.Failed)) revert InvalidPaymentStatus();

        payment.status = PaymentStatus.Failed;
        emit PaymentFailed(paymentId, reason);

        payment.status = PaymentStatus.Refunded;
        vault.pushTokens(payment.sourceToken, payment.sender, payment.amount);
        emit PaymentRefunded(paymentId, payment.amount);
    }

    /// @notice Mark a payment as failed (called by authorized adapters on timeout/bridge failure)
    function markPaymentFailed(bytes32 paymentId, string calldata reason) external {
        if (!isAuthorizedAdapter[msg.sender]) revert NotAuthorizedAdapter();
        Payment storage payment = payments[paymentId];
        if (payment.sender == address(0)) revert PaymentNotFound();
        payment.status = PaymentStatus.Failed;
        emit PaymentFailed(paymentId, reason);
    }
    
    function getPayment(bytes32 paymentId) external view override returns (Payment memory) {
        return payments[paymentId];
    }
    
}
