// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/IBridgeAdapter.sol";
import "../../vaults/PaymentKitaVault.sol";
import "./IStargate.sol";
import "./StargateOptionsBuilder.sol";

interface IStargatePrivacyMetadataGateway {
    function privacyStealthByPayment(bytes32 paymentId) external view returns (address);
    function privacyFinalReceiverByPayment(bytes32 paymentId) external view returns (address);
    function privacyIntentByPayment(bytes32 paymentId) external view returns (bytes32);
}

contract StargateSenderAdapter is IBridgeAdapter, Ownable {
    using SafeERC20 for IERC20;

    uint8 public constant PAYLOAD_VERSION_V1 = 1;
    uint16 public constant DEFAULT_COMPOSE_INDEX = 0;
    uint128 public constant DEFAULT_COMPOSE_GAS = 250_000;

    PaymentKitaVault public vault;
    IStargatePrivacyMetadataGateway public gateway;
    address public router;

    mapping(string => address) public stargates;
    mapping(string => uint32) public dstEids;
    mapping(string => bytes32) public destinationAdapters;
    mapping(string => bytes) public destinationExtraOptions;
    mapping(string => uint128) public destinationComposeGasLimits;

    event RouteSet(string indexed destChainId, address indexed stargate, uint32 dstEid, bytes32 destinationAdapter);
    event RouterUpdated(address indexed oldRouter, address indexed newRouter);
    event VaultUpdated(address indexed oldVault, address indexed newVault);
    event GatewayUpdated(address indexed oldGateway, address indexed newGateway);
    event DestinationExtraOptionsSet(string indexed destChainId, bytes extraOptions);
    event DestinationComposeGasLimitSet(string indexed destChainId, uint128 gasLimit);
    event StargateMessageSent(
        bytes32 indexed paymentId,
        bytes32 indexed guid,
        string indexed destChainId,
        address stargate,
        address token,
        uint256 amountSentLD,
        uint256 amountReceivedLD
    );

    error NotRouter();
    error ZeroAddress();
    error RouteNotConfigured(string destChainId);
    error InvalidReceiver();
    error InvalidPayer();
    error InvalidSourceToken(address expected, address actual);
    error NativeAssetUnsupported();
    error InsufficientNativeFee(uint256 required, uint256 provided);
    error PrivacyContextInvalid();
    error PrivacyReceiverMismatch(address expectedStealth, address messageReceiver);
    error NativeFeeRefundFailed(address payer, uint256 amount);

    constructor(address _vault, address _gateway, address _router) Ownable(msg.sender) {
        if (_vault == address(0) || _gateway == address(0) || _router == address(0)) revert ZeroAddress();
        vault = PaymentKitaVault(_vault);
        gateway = IStargatePrivacyMetadataGateway(_gateway);
        router = _router;
    }

    modifier onlyRouter() {
        if (msg.sender != router) revert NotRouter();
        _;
    }

    function setRoute(
        string calldata destChainId,
        address stargate,
        uint32 dstEid,
        bytes32 destinationAdapter
    ) external onlyOwner {
        if (stargate == address(0) || dstEid == 0 || destinationAdapter == bytes32(0)) revert ZeroAddress();
        stargates[destChainId] = stargate;
        dstEids[destChainId] = dstEid;
        destinationAdapters[destChainId] = destinationAdapter;
        emit RouteSet(destChainId, stargate, dstEid, destinationAdapter);
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

    function setGateway(address _gateway) external onlyOwner {
        if (_gateway == address(0)) revert ZeroAddress();
        emit GatewayUpdated(address(gateway), _gateway);
        gateway = IStargatePrivacyMetadataGateway(_gateway);
    }

    function setDestinationExtraOptions(string calldata destChainId, bytes calldata extraOptions) external onlyOwner {
        destinationExtraOptions[destChainId] = extraOptions;
        emit DestinationExtraOptionsSet(destChainId, extraOptions);
    }

    function setDestinationComposeGasLimit(string calldata destChainId, uint128 gasLimit) external onlyOwner {
        destinationComposeGasLimits[destChainId] = gasLimit;
        emit DestinationComposeGasLimitSet(destChainId, gasLimit);
    }

    function quoteFee(BridgeMessage calldata message) external view override returns (uint256 fee) {
        IStargate stargate = _requireRoute(message.destChainId);
        IStargate.SendParam memory sendParam = _buildSendParam(message, stargate, false);
        IStargate.MessagingFee memory quoted = stargate.quoteSend(sendParam, false);
        return quoted.nativeFee;
    }

    function sendMessage(BridgeMessage calldata message) external payable override onlyRouter returns (bytes32 messageId) {
        if (message.receiver == address(0)) revert InvalidReceiver();
        if (message.payer == address(0)) revert InvalidPayer();

        IStargate stargate = _requireRoute(message.destChainId);
        address routeToken = stargate.token();
        if (routeToken == address(0)) revert NativeAssetUnsupported();
        if (routeToken != message.sourceToken) revert InvalidSourceToken(routeToken, message.sourceToken);

        IStargate.SendParam memory sendParam = _buildSendParam(message, stargate, true);
        IStargate.MessagingFee memory fee = stargate.quoteSend(sendParam, false);
        if (msg.value < fee.nativeFee) revert InsufficientNativeFee(fee.nativeFee, msg.value);

        vault.pushTokens(message.sourceToken, address(this), message.amount);
        IERC20(message.sourceToken).forceApprove(address(stargate), 0);
        IERC20(message.sourceToken).forceApprove(address(stargate), message.amount);

        (
            IStargate.MessagingReceipt memory msgReceipt,
            IStargate.OFTReceipt memory oftReceipt,
            IStargate.Ticket memory ticket
        ) = stargate.sendToken{value: fee.nativeFee}(sendParam, fee, message.payer);
        ticket;

        uint256 refund = msg.value - fee.nativeFee;
        if (refund > 0) {
            (bool ok, ) = payable(message.payer).call{value: refund}("");
            if (!ok) revert NativeFeeRefundFailed(message.payer, refund);
        }

        emit StargateMessageSent(
            message.paymentId,
            msgReceipt.guid,
            message.destChainId,
            address(stargate),
            message.sourceToken,
            oftReceipt.amountSentLD,
            oftReceipt.amountReceivedLD
        );

        return msgReceipt.guid;
    }

    function isRouteConfigured(string calldata destChainId) external view override returns (bool) {
        return stargates[destChainId] != address(0) && dstEids[destChainId] != 0 && destinationAdapters[destChainId] != bytes32(0);
    }

    function getRouteConfig(
        string calldata destChainId
    ) external view override returns (bool configured, bytes memory configA, bytes memory configB) {
        configured = stargates[destChainId] != address(0) && dstEids[destChainId] != 0 && destinationAdapters[destChainId] != bytes32(0);
        configA = abi.encode(stargates[destChainId], dstEids[destChainId], destinationComposeGasLimits[destChainId]);
        configB = abi.encode(destinationAdapters[destChainId], destinationExtraOptions[destChainId]);
    }

    function _requireRoute(string calldata destChainId) internal view returns (IStargate stargate) {
        address stargateAddress = stargates[destChainId];
        uint32 dstEid = dstEids[destChainId];
        bytes32 destinationAdapter = destinationAdapters[destChainId];
        if (stargateAddress == address(0) || dstEid == 0 || destinationAdapter == bytes32(0)) {
            revert RouteNotConfigured(destChainId);
        }
        stargate = IStargate(stargateAddress);
    }

    function _buildSendParam(
        BridgeMessage calldata message,
        IStargate stargate,
        bool includeQuote
    ) internal view returns (IStargate.SendParam memory sendParam) {
        bytes memory composePayload = _buildComposePayload(message);
        bytes memory extraOptions = destinationExtraOptions[message.destChainId];
        if (extraOptions.length == 0) {
            uint128 composeGasLimit = destinationComposeGasLimits[message.destChainId];
            if (composeGasLimit == 0) {
                composeGasLimit = DEFAULT_COMPOSE_GAS;
            }
            extraOptions = StargateOptionsBuilder.addExecutorLzComposeOption(
                StargateOptionsBuilder.newOptions(),
                DEFAULT_COMPOSE_INDEX,
                composeGasLimit,
                0
            );
        }

        sendParam = IStargate.SendParam({
            dstEid: dstEids[message.destChainId],
            to: destinationAdapters[message.destChainId],
            amountLD: message.amount,
            minAmountLD: 0,
            extraOptions: extraOptions,
            composeMsg: composePayload,
            oftCmd: bytes("")
        });

        if (includeQuote) {
            (, , IStargate.OFTReceipt memory receipt) = stargate.quoteOFT(sendParam);
            sendParam.minAmountLD = receipt.amountReceivedLD;
        }
    }

    function _buildComposePayload(BridgeMessage calldata message) internal view returns (bytes memory composePayload) {
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

        composePayload = abi.encode(
            PAYLOAD_VERSION_V1,
            message.paymentId,
            message.receiver,
            message.destToken,
            message.minAmountOut,
            isPrivacy,
            privacyIntentId,
            privacyStealth,
            privacyFinalReceiver,
            message.payer
        );
    }
}
