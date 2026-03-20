// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../src/PaymentKitaGateway.sol";
import "../src/PaymentKitaRouter.sol";
import "../src/vaults/PaymentKitaVault.sol";
import "../src/TokenRegistry.sol";
import "../src/interfaces/IPaymentKitaGateway.sol";
import "../src/interfaces/IBridgeAdapter.sol";
import "../src/interfaces/ISwapper.sol";
import "../src/gateway/modules/GatewayValidatorModule.sol";
import "../src/gateway/modules/GatewayQuoteModule.sol";
import "../src/gateway/modules/GatewayExecutionModule.sol";
import "../src/gateway/modules/GatewayPrivacyModule.sol";
import "../src/gateway/fee/FeePolicyManager.sol";
import "../src/gateway/fee/strategies/FeeStrategyDefaultV1.sol";
import "../src/privacy/StealthEscrow.sol";

contract MockTokenV2 is ERC20 {
    constructor(string memory n, string memory s) ERC20(n, s) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockNoopAdapterV2 is IBridgeAdapter {
    function sendMessage(BridgeMessage calldata message) external payable returns (bytes32) {
        return keccak256(abi.encode(message.paymentId, message.destChainId, message.amount, block.number));
    }

    function quoteFee(BridgeMessage calldata) external pure returns (uint256) {
        return 0;
    }

    function isRouteConfigured(string calldata) external pure returns (bool) {
        return true;
    }

    function getRouteConfig(
        string calldata
    ) external pure returns (bool configured, bytes memory configA, bytes memory configB) {
        return (true, bytes("ok"), bytes(""));
    }
}

contract MockFeeAdapterV2 is IBridgeAdapter {
    uint256 public quotedFee;

    function setQuotedFee(uint256 fee) external {
        quotedFee = fee;
    }

    function sendMessage(BridgeMessage calldata message) external payable returns (bytes32) {
        require(msg.value >= quotedFee, "fee_underpaid");
        return keccak256(abi.encode(message.paymentId, message.destChainId, message.amount, block.number));
    }

    function quoteFee(BridgeMessage calldata) external view returns (uint256) {
        return quotedFee;
    }

    function isRouteConfigured(string calldata) external pure returns (bool) {
        return true;
    }

    function getRouteConfig(
        string calldata
    ) external pure returns (bool configured, bytes memory configA, bytes memory configB) {
        return (true, bytes("ok"), bytes(""));
    }
}

contract MockGatewayAwarePrivacyAdapterV2 is IBridgeAdapter {
    PaymentKitaGateway public immutable gateway;

    bool public lastSawPrivacy;
    bytes32 public lastPaymentId;
    bytes32 public lastIntentId;
    address public lastStealthReceiver;
    address public lastFinalReceiver;
    address public lastSourceSender;

    constructor(address _gateway) {
        gateway = PaymentKitaGateway(_gateway);
    }

    function sendMessage(BridgeMessage calldata message) external payable returns (bytes32) {
        lastPaymentId = message.paymentId;
        lastIntentId = gateway.privacyIntentByPayment(message.paymentId);
        lastStealthReceiver = gateway.privacyStealthByPayment(message.paymentId);
        lastFinalReceiver = gateway.privacyFinalReceiverByPayment(message.paymentId);
        lastSourceSender = gateway.privacySourceSenderByPayment(message.paymentId);
        lastSawPrivacy =
            lastIntentId != bytes32(0) &&
            lastStealthReceiver != address(0) &&
            lastFinalReceiver != address(0) &&
            lastSourceSender != address(0);
        return keccak256(abi.encode(message.paymentId, message.destChainId, message.amount, block.number));
    }

    function quoteFee(BridgeMessage calldata) external pure returns (uint256) {
        return 0;
    }

    function isRouteConfigured(string calldata) external pure returns (bool) {
        return true;
    }

    function getRouteConfig(
        string calldata
    ) external pure returns (bool configured, bytes memory configA, bytes memory configB) {
        return (true, bytes("ok"), bytes(""));
    }
}

contract MockV2Swapper is ISwapper {
    using SafeERC20 for IERC20;

    PaymentKitaVault public immutable vault;
    mapping(bytes32 => bool) public routeExists;
    mapping(bytes32 => bool) public routeIsDirect;
    mapping(bytes32 => uint256) public routeRateWad;
    mapping(bytes32 => bool) public forceQuoteFail;

    constructor(address _vault) {
        vault = PaymentKitaVault(_vault);
    }

    function setRoute(address tokenIn, address tokenOut, bool exists, bool isDirect, uint256 rateWad) external {
        bytes32 k = keccak256(abi.encodePacked(tokenIn, tokenOut));
        routeExists[k] = exists;
        routeIsDirect[k] = isDirect;
        routeRateWad[k] = rateWad;
    }

    function setForceQuoteFail(address tokenIn, address tokenOut, bool shouldFail) external {
        bytes32 k = keccak256(abi.encodePacked(tokenIn, tokenOut));
        forceQuoteFail[k] = shouldFail;
    }

    function swapFromVault(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut) {
        vault.pushTokens(tokenIn, address(this), amountIn);
        amountOut = getQuote(tokenIn, tokenOut, amountIn);
        require(amountOut >= minAmountOut, "Mock slippage");
        IERC20(tokenOut).safeTransfer(recipient, amountOut);
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut) {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        amountOut = getQuote(tokenIn, tokenOut, amountIn);
        require(amountOut >= minAmountOut, "Mock slippage");
        IERC20(tokenOut).safeTransfer(recipient, amountOut);
    }

    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public view returns (uint256 amountOut) {
        bytes32 k = keccak256(abi.encodePacked(tokenIn, tokenOut));
        require(routeExists[k], "NoRoute");
        require(!forceQuoteFail[k], "ForcedQuoteFail");
        uint256 r = routeRateWad[k];
        if (r == 0) {
            r = 1e18;
        }
        return (amountIn * r) / 1e18;
    }

    function estimateSwapGas(
        address tokenIn,
        address tokenOut,
        uint256
    ) external view returns (uint256 estimatedGas, uint256 hopCount) {
        bytes32 k = keccak256(abi.encodePacked(tokenIn, tokenOut));
        require(routeExists[k], "NoRoute");
        return (150_000, routeIsDirect[k] ? 1 : 2);
    }

    function getSwapQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut, uint256 estimatedGas, uint256 hopCount, address[] memory path) {
        bytes32 k = keccak256(abi.encodePacked(tokenIn, tokenOut));
        require(routeExists[k], "NoRoute");
        amountOut = getQuote(tokenIn, tokenOut, amountIn);
        estimatedGas = 150_000;
        hopCount = routeIsDirect[k] ? 1 : 2;
        path = new address[](routeIsDirect[k] ? 2 : 3);
        path[0] = tokenIn;
        if (routeIsDirect[k]) {
            path[1] = tokenOut;
        } else {
            path[1] = address(0xBEEF);
            path[2] = tokenOut;
        }
    }

    function findRoute(
        address tokenIn,
        address tokenOut
    ) external view returns (bool exists, bool isDirect, address[] memory path) {
        bytes32 k = keccak256(abi.encodePacked(tokenIn, tokenOut));
        exists = routeExists[k];
        isDirect = routeIsDirect[k];
        if (!exists) {
            return (false, false, new address[](0));
        }
        path = new address[](isDirect ? 2 : 3);
        path[0] = tokenIn;
        if (isDirect) {
            path[1] = tokenOut;
        } else {
            path[1] = address(0xBEEF);
            path[2] = tokenOut;
        }
    }
}

contract PaymentKitaGatewayV2Phase1Test is Test {
    PaymentKitaGateway gateway;
    PaymentKitaRouter router;
    PaymentKitaVault vault;
    TokenRegistry registry;
    MockNoopAdapterV2 adapter;
    MockFeeAdapterV2 feeAdapter;
    MockGatewayAwarePrivacyAdapterV2 privacyAwareAdapter;
    MockV2Swapper swapper;
    GatewayValidatorModule validatorModule;
    GatewayQuoteModule quoteModule;
    GatewayExecutionModule executionModule;
    GatewayPrivacyModule privacyModule;
    FeePolicyManager feePolicyManager;
    FeeStrategyDefaultV1 defaultStrategy;
    MockTokenV2 sourceToken;
    MockTokenV2 bridgeToken;
    MockTokenV2 destToken;

    address user = address(0x1111);
    address receiver = address(0x2222);
    string constant DEST = "eip155:137";
    string constant DEST_2 = "eip155:42161";

    function setUp() public {
        sourceToken = new MockTokenV2("Source", "SRC");
        bridgeToken = new MockTokenV2("Bridge", "BRG");
        destToken = new MockTokenV2("Dest", "DST");

        registry = new TokenRegistry();
        vault = new PaymentKitaVault();
        router = new PaymentKitaRouter();
        gateway = new PaymentKitaGateway(address(vault), address(router), address(registry), address(this));
        adapter = new MockNoopAdapterV2();
        feeAdapter = new MockFeeAdapterV2();
        privacyAwareAdapter = new MockGatewayAwarePrivacyAdapterV2(address(gateway));
        swapper = new MockV2Swapper(address(vault));
        validatorModule = new GatewayValidatorModule();
        quoteModule = new GatewayQuoteModule();
        executionModule = new GatewayExecutionModule();
        privacyModule = new GatewayPrivacyModule();
        defaultStrategy = new FeeStrategyDefaultV1(address(registry));
        feePolicyManager = new FeePolicyManager(address(defaultStrategy));

        registry.setTokenSupport(address(sourceToken), true);
        registry.setTokenSupport(address(bridgeToken), true);
        registry.setTokenSupport(address(destToken), true);

        router.registerAdapter(DEST, 1, address(adapter));
        gateway.setDefaultBridgeType(DEST, 1);
        router.registerAdapter(DEST_2, 1, address(adapter));
        gateway.setDefaultBridgeType(DEST_2, 1);
        router.registerAdapter("eip155:10", 1, address(feeAdapter));
        gateway.setDefaultBridgeType("eip155:10", 1);
        gateway.setGatewayModules(
            address(validatorModule),
            address(quoteModule),
            address(executionModule),
            address(privacyModule)
        );
        gateway.setFeePolicyManager(address(feePolicyManager));
        privacyModule.setAuthorizedGateway(address(gateway), true);

        vault.setAuthorizedSpender(address(gateway), true);
        vault.setAuthorizedSpender(address(adapter), true);
        vault.setAuthorizedSpender(address(swapper), true);

        gateway.setSwapper(address(swapper));
        gateway.setEnableSourceSideSwap(true);
        gateway.setBridgeTokenForDest(DEST, address(bridgeToken));

        sourceToken.mint(user, 10_000e18);
        bridgeToken.mint(user, 10_000e18);
        bridgeToken.mint(address(swapper), 10_000e18);
    }

    function _baseReq(
        address src,
        address bridgeSrc,
        address dst
    ) internal view returns (IPaymentKitaGateway.PaymentRequestV2 memory req) {
        req.destChainIdBytes = bytes(DEST);
        req.receiverBytes = abi.encode(receiver);
        req.sourceToken = src;
        req.bridgeTokenSource = bridgeSrc;
        req.destToken = dst;
        req.amountInSource = 100e18;
        req.minBridgeAmountOut = 90e18;
        req.minDestAmountOut = 0;
        req.mode = IPaymentKitaGateway.PaymentMode.REGULAR;
        req.bridgeOption = 255;
    }

    function _deployStealthEscrow() internal returns (address) {
        StealthEscrow escrow = new StealthEscrow(address(this), address(privacyModule));
        return address(escrow);
    }

    function _configureTokenBridgeType3(bool supportsDestSwap, bool supportsPrivacySettlement) internal {
        router.registerAdapter(DEST, 3, address(adapter));
        gateway.setDefaultBridgeType(DEST, 3);
        router.setBridgeMode(3, PaymentKitaRouter.BridgeMode.TOKEN_BRIDGE);
        router.setTokenBridgeDestSwapCapability(3, supportsDestSwap);
        router.setTokenBridgePrivacySettlementCapability(3, supportsPrivacySettlement);
    }

    function testV2CreatePayment_NormalizesSourceToBridgeToken() public {
        swapper.setRoute(address(sourceToken), address(bridgeToken), true, false, 1e18);

        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(sourceToken), address(0), address(destToken));
        vm.startPrank(user);
        sourceToken.approve(address(vault), type(uint256).max);
        bytes32 pid = gateway.createPayment(req);
        vm.stopPrank();
        assertTrue(pid != bytes32(0));
    }

    function testV2QuotePaymentCost_NoRouteToBridgeToken() public {
        // no swapper route configured
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(sourceToken), address(0), address(destToken));

        (, , , , bool bridgeQuoteOk, string memory bridgeQuoteReason) = gateway.quotePaymentCost(req);
        assertFalse(bridgeQuoteOk);
        assertEq(bridgeQuoteReason, "no_route_to_bridge_token");
    }

    function testV2CreatePayment_RevertBridgeTokenNotConfigured() public {
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(sourceToken), address(0), address(destToken));
        req.destChainIdBytes = bytes(DEST_2); // has adapter/default bridge but no lane bridge token mapping

        vm.startPrank(user);
        sourceToken.approve(address(vault), type(uint256).max);
        vm.expectRevert(PaymentKitaGateway.BridgeTokenNotConfigured.selector);
        gateway.createPayment(req);
        vm.stopPrank();
    }

    function testV2CreatePayment_WorksWithDefaultBridgeMapping() public {
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        bytes32 pid = gateway.createPayment(req);
        vm.stopPrank();

        assertTrue(pid != bytes32(0));
    }

    function testV2CreatePayment_AcceptsExplicitBridgeOptionTokenGateway() public {
        _configureTokenBridgeType3(true, false);

        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.bridgeOption = 3;

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        bytes32 pid = gateway.createPayment(req);
        vm.stopPrank();

        assertTrue(pid != bytes32(0));
        assertEq(gateway.paymentBridgeType(pid), 3);
    }

    function testPrivacyCrossChainV2_StealthReceiverAndIntentStored() public {
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.mode = IPaymentKitaGateway.PaymentMode.PRIVACY;

        IPaymentKitaGateway.PrivateRouting memory privacy;
        privacy.intentId = keccak256("intent-1");
        privacy.stealthReceiver = _deployStealthEscrow();

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        bytes32 pid = gateway.createPaymentPrivate(req, privacy);
        vm.stopPrank();

        IPaymentKitaGateway.Payment memory payment = gateway.getPayment(pid);
        address storedReceiver = payment.receiver;
        assertEq(storedReceiver, privacy.stealthReceiver);
        assertEq(gateway.privacyIntentByPayment(pid), privacy.intentId);
        assertEq(gateway.privacyStealthByPayment(pid), privacy.stealthReceiver);
        assertEq(gateway.privacyFinalReceiverByPayment(pid), receiver);
        assertEq(gateway.privacyForwardCompleted(pid), false);
    }

    function testPrivacyCrossChainV2_MetadataVisibleToAdapterDuringRouting() public {
        router.registerAdapter(DEST, 2, address(privacyAwareAdapter));
        gateway.setDefaultBridgeType(DEST, 2);

        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.mode = IPaymentKitaGateway.PaymentMode.PRIVACY;
        req.bridgeOption = 2;

        IPaymentKitaGateway.PrivateRouting memory privacy;
        privacy.intentId = keccak256("intent-visible-during-route");
        privacy.stealthReceiver = _deployStealthEscrow();

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        bytes32 pid = gateway.createPaymentPrivate(req, privacy);
        vm.stopPrank();

        assertEq(privacyAwareAdapter.lastPaymentId(), pid);
        assertTrue(privacyAwareAdapter.lastSawPrivacy());
        assertEq(privacyAwareAdapter.lastIntentId(), privacy.intentId);
        assertEq(privacyAwareAdapter.lastStealthReceiver(), privacy.stealthReceiver);
        assertEq(privacyAwareAdapter.lastFinalReceiver(), receiver);
        assertEq(privacyAwareAdapter.lastSourceSender(), user);
    }

    function testPrivacySameChainV2_AutoForwardTriggeredAtGateway() public {
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(bridgeToken));
        req.destChainIdBytes = bytes(string(abi.encodePacked("eip155:", vm.toString(block.chainid))));
        req.mode = IPaymentKitaGateway.PaymentMode.PRIVACY;

        IPaymentKitaGateway.PrivateRouting memory privacy;
        privacy.intentId = keccak256("intent-samechain-auto-forward");
        privacy.stealthReceiver = _deployStealthEscrow();

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        bytes32 pid = gateway.createPaymentPrivate(req, privacy);
        vm.stopPrank();

        assertEq(gateway.privacyForwardCompleted(pid), true);
        assertEq(gateway.privacyForwardRetryCount(pid), 0);
        assertEq(gateway.paymentSettledToken(pid), address(bridgeToken));
        assertEq(gateway.paymentSettledAmount(pid), req.amountInSource);
    }

    function testPrivacyV2_RevertWhenStealthEqualsFinalReceiver() public {
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.mode = IPaymentKitaGateway.PaymentMode.PRIVACY;

        IPaymentKitaGateway.PrivateRouting memory privacy;
        privacy.intentId = keccak256("intent-stealth-equals-final");
        privacy.stealthReceiver = receiver;

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        vm.expectRevert(PaymentKitaGateway.StealthReceiverMustDiffer.selector);
        gateway.createPaymentPrivate(req, privacy);
        vm.stopPrank();
    }

    function testPrivacyForwardFinalize_AuthorizedAdapterMarksCompleted() public {
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.mode = IPaymentKitaGateway.PaymentMode.PRIVACY;

        IPaymentKitaGateway.PrivateRouting memory privacy;
        privacy.intentId = keccak256("intent-forward-ok");
        privacy.stealthReceiver = _deployStealthEscrow();

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        bytes32 pid = gateway.createPaymentPrivate(req, privacy);
        vm.stopPrank();

        destToken.mint(privacy.stealthReceiver, 77e18);

        vm.prank(address(adapter));
        gateway.finalizePrivacyForward(pid, address(destToken), 77e18);

        assertEq(gateway.privacyForwardCompleted(pid), true);

        vm.prank(address(adapter));
        vm.expectRevert(PaymentKitaGateway.PrivacyForwardAlreadyCompleted.selector);
        gateway.finalizePrivacyForward(pid, address(destToken), 77e18);
    }

    function testPrivacyForwardFailure_AuthorizedAdapterIncrementsRetry() public {
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.mode = IPaymentKitaGateway.PaymentMode.PRIVACY;

        IPaymentKitaGateway.PrivateRouting memory privacy;
        privacy.intentId = keccak256("intent-forward-fail");
        privacy.stealthReceiver = address(0xABCD);

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        bytes32 pid = gateway.createPaymentPrivate(req, privacy);
        vm.stopPrank();

        vm.prank(address(adapter));
        gateway.reportPrivacyForwardFailure(pid, "fail-1");
        assertEq(gateway.privacyForwardRetryCount(pid), 1);

        vm.prank(address(adapter));
        gateway.reportPrivacyForwardFailure(pid, "fail-2");
        assertEq(gateway.privacyForwardRetryCount(pid), 2);
    }

    function testPrivacyForward_RevertWhenUnauthorized() public {
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.mode = IPaymentKitaGateway.PaymentMode.PRIVACY;

        IPaymentKitaGateway.PrivateRouting memory privacy;
        privacy.intentId = keccak256("intent-forward-unauth");
        privacy.stealthReceiver = address(0xABCD);

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        bytes32 pid = gateway.createPaymentPrivate(req, privacy);
        vm.stopPrank();

        vm.expectRevert(PaymentKitaGateway.UnauthorizedAdapter.selector);
        gateway.finalizePrivacyForward(pid, address(destToken), 1e18);

        vm.expectRevert(PaymentKitaGateway.UnauthorizedAdapter.selector);
        gateway.reportPrivacyForwardFailure(pid, "fail");
    }

    function testPrivacyRecoveryRetry_CrossChainSenderCanRetry() public {
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.mode = IPaymentKitaGateway.PaymentMode.PRIVACY;

        IPaymentKitaGateway.PrivateRouting memory privacy;
        privacy.intentId = keccak256("intent-retry");
        privacy.stealthReceiver = _deployStealthEscrow();

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        bytes32 pid = gateway.createPaymentPrivate(req, privacy);
        vm.stopPrank();

        uint256 settled = 33e18;
        vm.prank(address(adapter));
        gateway.finalizeIncomingPayment(pid, privacy.stealthReceiver, address(destToken), settled);

        vm.prank(address(adapter));
        gateway.reportPrivacyForwardFailure(pid, "FORWARD_FAIL");
        assertEq(gateway.privacyForwardRetryCount(pid), 1);

        destToken.mint(privacy.stealthReceiver, settled);

        vm.prank(user);
        gateway.retryPrivacyForward(pid);

        assertEq(gateway.privacyForwardCompleted(pid), true);
        assertEq(destToken.balanceOf(receiver), settled);
    }

    function testPrivacyRecoveryRetry_RevertWhenNoFailureYet() public {
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.mode = IPaymentKitaGateway.PaymentMode.PRIVACY;

        IPaymentKitaGateway.PrivateRouting memory privacy;
        privacy.intentId = keccak256("intent-no-retry-needed");
        privacy.stealthReceiver = _deployStealthEscrow();

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        bytes32 pid = gateway.createPaymentPrivate(req, privacy);
        vm.stopPrank();

        uint256 settled = 11e18;
        vm.prank(address(adapter));
        gateway.finalizeIncomingPayment(pid, privacy.stealthReceiver, address(destToken), settled);

        destToken.mint(privacy.stealthReceiver, settled);

        vm.prank(user);
        vm.expectRevert(PaymentKitaGateway.PrivacyRetryNotAvailable.selector);
        gateway.retryPrivacyForward(pid);
    }

    function testPrivacyRecoveryClaim_CrossChainFinalReceiverCanClaim() public {
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.mode = IPaymentKitaGateway.PaymentMode.PRIVACY;

        IPaymentKitaGateway.PrivateRouting memory privacy;
        privacy.intentId = keccak256("intent-claim");
        privacy.stealthReceiver = _deployStealthEscrow();

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        bytes32 pid = gateway.createPaymentPrivate(req, privacy);
        vm.stopPrank();

        uint256 settled = 21e18;
        vm.prank(address(adapter));
        gateway.finalizeIncomingPayment(pid, privacy.stealthReceiver, address(destToken), settled);
        destToken.mint(privacy.stealthReceiver, settled);

        vm.prank(receiver);
        gateway.claimPrivacyEscrow(pid);

        assertEq(gateway.privacyForwardCompleted(pid), true);
        assertEq(destToken.balanceOf(receiver), settled);
    }

    function testPrivacyRecoveryClaim_RevertWhenUnauthorized() public {
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.mode = IPaymentKitaGateway.PaymentMode.PRIVACY;

        IPaymentKitaGateway.PrivateRouting memory privacy;
        privacy.intentId = keccak256("intent-claim-unauth");
        privacy.stealthReceiver = _deployStealthEscrow();

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        bytes32 pid = gateway.createPaymentPrivate(req, privacy);
        vm.stopPrank();

        uint256 settled = 8e18;
        vm.prank(address(adapter));
        gateway.finalizeIncomingPayment(pid, privacy.stealthReceiver, address(destToken), settled);
        destToken.mint(privacy.stealthReceiver, settled);

        vm.prank(address(0x3333));
        vm.expectRevert(PaymentKitaGateway.PrivacyRecoveryUnauthorized.selector);
        gateway.claimPrivacyEscrow(pid);
    }

    function testPrivacyRecoveryRefund_CrossChainSenderCanRefund() public {
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.mode = IPaymentKitaGateway.PaymentMode.PRIVACY;

        IPaymentKitaGateway.PrivateRouting memory privacy;
        privacy.intentId = keccak256("intent-refund");
        privacy.stealthReceiver = _deployStealthEscrow();

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        bytes32 pid = gateway.createPaymentPrivate(req, privacy);
        vm.stopPrank();

        uint256 settled = 19e18;
        vm.prank(address(adapter));
        gateway.finalizeIncomingPayment(pid, privacy.stealthReceiver, address(destToken), settled);
        destToken.mint(privacy.stealthReceiver, settled);

        vm.prank(user);
        gateway.refundPrivacyEscrow(pid);

        assertEq(gateway.privacyForwardCompleted(pid), true);
        assertEq(destToken.balanceOf(user), settled);
    }

    function testPrivacyRecoveryRetry_IncomingContextWithoutSourcePaymentState() public {
        bytes32 pid = keccak256("incoming-privacy-retry");
        bytes32 intentId = keccak256("incoming-intent-retry");
        address stealth = _deployStealthEscrow();
        uint256 settled = 13e18;

        gateway.setAuthorizedAdapter(address(adapter), true);

        vm.prank(address(adapter));
        gateway.registerIncomingPrivacyContext(pid, intentId, stealth, receiver, user);

        vm.prank(address(adapter));
        gateway.finalizeIncomingPayment(pid, stealth, address(destToken), settled);

        vm.prank(address(adapter));
        gateway.reportPrivacyForwardFailure(pid, "INCOMING_FORWARD_FAILED");

        destToken.mint(stealth, settled);

        vm.prank(user);
        gateway.retryPrivacyForward(pid);

        assertEq(gateway.privacyIntentByPayment(pid), intentId);
        assertEq(gateway.privacySourceSenderByPayment(pid), user);
        assertEq(gateway.privacyForwardCompleted(pid), true);
        assertEq(destToken.balanceOf(receiver), settled);
    }

    function testPrivacyRecoveryRefund_IncomingContextWithoutSourcePaymentState() public {
        bytes32 pid = keccak256("incoming-privacy-refund");
        bytes32 intentId = keccak256("incoming-intent-refund");
        address stealth = _deployStealthEscrow();
        uint256 settled = 17e18;

        gateway.setAuthorizedAdapter(address(adapter), true);

        vm.prank(address(adapter));
        gateway.registerIncomingPrivacyContext(pid, intentId, stealth, receiver, user);

        vm.prank(address(adapter));
        gateway.finalizeIncomingPayment(pid, stealth, address(destToken), settled);

        destToken.mint(stealth, settled);

        vm.prank(user);
        gateway.refundPrivacyEscrow(pid);

        assertEq(gateway.privacyForwardCompleted(pid), true);
        assertEq(destToken.balanceOf(user), settled);
    }

    function testV2CreatePayment_RevertInvalidBridgeOption() public {
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.bridgeOption = 9;

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        vm.expectRevert();
        gateway.createPayment(req);
        vm.stopPrank();
    }

    function testV2CreatePayment_RevertWhenSourceSideSwapDisabled() public {
        gateway.setEnableSourceSideSwap(false);
        swapper.setRoute(address(sourceToken), address(bridgeToken), true, false, 1e18);

        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(sourceToken), address(0), address(destToken));
        vm.startPrank(user);
        sourceToken.approve(address(vault), type(uint256).max);
        vm.expectRevert(PaymentKitaGateway.SourceSideSwapDisabled.selector);
        gateway.createPayment(req);
        vm.stopPrank();
    }

    function testV2CreatePayment_RevertWhenNoRouteToBridgeToken() public {
        // source -> bridge route intentionally not configured
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(sourceToken), address(0), address(destToken));

        vm.startPrank(user);
        sourceToken.approve(address(vault), type(uint256).max);
        vm.expectRevert(PaymentKitaGateway.NoRouteToBridgeToken.selector);
        gateway.createPayment(req);
        vm.stopPrank();
    }

    function testV2CreatePayment_RevertInsufficientNativeFeeAfterQuote() public {
        // route that does not require source swap to isolate fee failure
        gateway.setBridgeTokenForDest("eip155:10", address(bridgeToken));
        feeAdapter.setQuotedFee(1e15);

        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.destChainIdBytes = bytes("eip155:10");

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                GatewayExecutionModule.InsufficientNativeFee.selector,
                0,
                1e15
            )
        );
        gateway.createPayment(req);
        vm.stopPrank();
    }

    function testV2CreatePaymentDefaultBridge_IgnoresReqBridgeOptionAndUsesDefault() public {
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.bridgeOption = 2; // LZ, but wrapper should force DEFAULT.

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        bytes32 pid = gateway.createPaymentDefaultBridge(req);
        vm.stopPrank();

        assertTrue(pid != bytes32(0));
        assertEq(gateway.paymentBridgeType(pid), gateway.defaultBridgeTypes(DEST));
    }

    function testV2QuotePaymentCost_ReasonSourceSideSwapDisabled() public {
        gateway.setEnableSourceSideSwap(false);
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(sourceToken), address(0), address(destToken));

        (, , , uint8 bridgeType, bool bridgeQuoteOk, string memory reason) = gateway.quotePaymentCost(req);
        assertEq(bridgeType, 1);
        assertFalse(bridgeQuoteOk);
        assertEq(reason, "source_side_swap_disabled");
    }

    function testV2QuotePaymentCost_ReasonSwapperNotConfigured() public {
        gateway.setSwapper(address(0));
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(sourceToken), address(0), address(destToken));

        (, , , uint8 bridgeType, bool bridgeQuoteOk, string memory reason) = gateway.quotePaymentCost(req);
        assertEq(bridgeType, 1);
        assertFalse(bridgeQuoteOk);
        assertEq(reason, "swapper_not_configured");
    }

    function testV2QuotePaymentCost_ReasonSourceSwapQuoteFailed() public {
        swapper.setRoute(address(sourceToken), address(bridgeToken), true, false, 1e18);
        swapper.setForceQuoteFail(address(sourceToken), address(bridgeToken), true);
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(sourceToken), address(0), address(destToken));

        (, , , uint8 bridgeType, bool bridgeQuoteOk, string memory reason) = gateway.quotePaymentCost(req);
        assertEq(bridgeType, 1);
        assertFalse(bridgeQuoteOk);
        assertEq(reason, "source_swap_quote_failed");
    }

    function testV2QuotePaymentCost_ReasonInvalidBridgeOption() public {
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.bridgeOption = 9;

        (, , , uint8 bridgeType, bool bridgeQuoteOk, string memory reason) = gateway.quotePaymentCost(req);
        assertEq(bridgeType, 255);
        assertFalse(bridgeQuoteOk);
        assertEq(reason, "invalid_bridge_option");
    }

    function testV2QuotePaymentCost_ReasonBridgeRouteNotConfigured() public {
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.bridgeOption = 2; // no adapter for this bridge type in setup

        (, , , uint8 bridgeType, bool bridgeQuoteOk, string memory reason) = gateway.quotePaymentCost(req);
        assertEq(bridgeType, 2);
        assertFalse(bridgeQuoteOk);
        assertEq(reason, "bridge_route_not_configured");
    }

    function testV2QuotePaymentCost_TokenBridgeType3CrossTokenRequiresDestSwapCapability() public {
        _configureTokenBridgeType3(false, false);

        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));

        (, , , uint8 bridgeType, bool bridgeQuoteOk, string memory reason) = gateway.quotePaymentCost(req);
        assertEq(bridgeType, 3);
        assertFalse(bridgeQuoteOk);
        assertEq(reason, "TOKEN_BRIDGE requires same token");
    }

    function testV2QuotePaymentCost_TokenBridgeType3CrossTokenAllowedWhenDestSwapEnabled() public {
        _configureTokenBridgeType3(true, false);

        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));

        (, uint256 bridgeFeeNative,, uint8 bridgeType, bool bridgeQuoteOk, string memory reason) = gateway
            .quotePaymentCost(req);
        assertEq(bridgeType, 3);
        assertTrue(bridgeQuoteOk);
        assertEq(bytes(reason).length, 0);
        assertEq(bridgeFeeNative, 0);
    }

    function testV2QuotePaymentCost_PrivacyTokenBridgeType3RequiresPrivacySettlementCapability() public {
        _configureTokenBridgeType3(true, false);

        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.mode = IPaymentKitaGateway.PaymentMode.PRIVACY;

        (, , , uint8 bridgeType, bool bridgeQuoteOk, string memory reason) = gateway.quotePaymentCost(req);
        assertEq(bridgeType, 3);
        assertFalse(bridgeQuoteOk);
        assertEq(reason, "token_bridge_privacy_settlement_unsupported");
    }

    function testV2QuotePaymentCost_ReasonBridgeTokenNotConfigured() public {
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(sourceToken), address(0), address(destToken));
        req.destChainIdBytes = bytes(DEST_2); // has route but no bridge-token lane mapping

        (, , , uint8 bridgeType, bool bridgeQuoteOk, string memory reason) = gateway.quotePaymentCost(req);
        assertEq(bridgeType, 1);
        assertFalse(bridgeQuoteOk);
        assertEq(reason, "bridge_token_not_configured");
    }

    function testV2QuotePaymentCost_ReasonBridgeTokenNotSupported() public {
        MockTokenV2 unsupportedBridge = new MockTokenV2("UnsupportedBridge", "UBRG");
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(sourceToken), address(unsupportedBridge), address(destToken));

        (, , , uint8 bridgeType, bool bridgeQuoteOk, string memory reason) = gateway.quotePaymentCost(req);
        assertEq(bridgeType, 1);
        assertFalse(bridgeQuoteOk);
        assertEq(reason, "bridge_token_not_supported");
    }

    function testV2QuotePaymentCost_ReasonQuoteModuleNotConfigured() public {
        PaymentKitaGateway gatewayNoModules = new PaymentKitaGateway(address(vault), address(router), address(registry), address(this));
        gatewayNoModules.setFeePolicyManager(address(feePolicyManager));
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.bridgeOption = 1;
        req.bridgeTokenSource = address(bridgeToken);

        (
            uint256 platformFee,
            uint256 bridgeFeeNative,
            uint256 totalSourceTokenRequired,
            uint8 bridgeType,
            bool bridgeQuoteOk,
            string memory reason
        ) = gatewayNoModules.quotePaymentCost(req);
        assertEq(bridgeType, 1);
        assertFalse(bridgeQuoteOk);
        assertEq(reason, "quote_module_not_configured");
        assertEq(bridgeFeeNative, 0);
        assertGt(platformFee, 0);
        assertEq(totalSourceTokenRequired, req.amountInSource + platformFee);
    }

    function testV2QuotePaymentCost_ReasonAmountMustBeGtZero() public {
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.amountInSource = 0;

        (
            uint256 platformFee,
            uint256 bridgeFeeNative,
            uint256 totalSourceTokenRequired,
            uint8 bridgeType,
            bool bridgeQuoteOk,
            string memory reason
        ) = gateway.quotePaymentCost(req);
        assertEq(bridgeType, 255);
        assertFalse(bridgeQuoteOk);
        assertEq(reason, "amount_must_be_gt_zero");
        assertEq(platformFee, 0);
        assertEq(bridgeFeeNative, 0);
        assertEq(totalSourceTokenRequired, 0);
    }

    function testPreviewApprovalV2_AppliesNativeFeeBuffer() public {
        gateway.setBridgeTokenForDest("eip155:10", address(bridgeToken));
        feeAdapter.setQuotedFee(1e15); // 0.001 native

        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.destChainIdBytes = bytes("eip155:10");

        (uint256 platformFee,,,,,) = gateway.quotePaymentCost(req);
        (address approvalToken, uint256 approvalAmount, uint256 requiredNativeFee) = gateway.previewApproval(req);

        assertEq(approvalToken, address(bridgeToken));
        assertEq(approvalAmount, req.amountInSource + platformFee);
        // default buffer = 500 bps => +5%
        assertEq(requiredNativeFee, 1_050_000_000_000_000);
    }

    function testPreviewApprovalV2_ZeroNativeFeeWhenQuoteUnhealthy() public {
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.bridgeOption = 2; // unconfigured route, quote must be unhealthy

        (uint256 platformFee,,,,,) = gateway.quotePaymentCost(req);
        (, uint256 approvalAmount, uint256 requiredNativeFee) = gateway.previewApproval(req);
        assertEq(approvalAmount, req.amountInSource + platformFee);
        assertEq(requiredNativeFee, 0);
    }

    function testV2CreatePayment_RevertBridgeOptionRouteMissing() public {
        // Explicit LayerZero option (2) has no registered adapter in setup.
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.bridgeOption = 2;

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentKitaGateway.BridgeRouteNotConfigured.selector,
                DEST,
                uint8(2)
            )
        );
        gateway.createPayment(req);
        vm.stopPrank();
    }

    function testPrivacyV2_RevertWhenIntentMissing() public {
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.mode = IPaymentKitaGateway.PaymentMode.PRIVACY;

        IPaymentKitaGateway.PrivateRouting memory privacy;
        privacy.intentId = bytes32(0);
        privacy.stealthReceiver = address(0xABCD);

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        vm.expectRevert(PaymentKitaGateway.MissingPrivacyIntent.selector);
        gateway.createPaymentPrivate(req, privacy);
        vm.stopPrank();
    }

    function testPrivacyV2_RevertWhenStealthReceiverZero() public {
        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.mode = IPaymentKitaGateway.PaymentMode.PRIVACY;

        IPaymentKitaGateway.PrivateRouting memory privacy;
        privacy.intentId = keccak256("intent-zero-stealth");
        privacy.stealthReceiver = address(0);

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        vm.expectRevert(PaymentKitaGateway.InvalidStealthReceiver.selector);
        gateway.createPaymentPrivate(req, privacy);
        vm.stopPrank();
    }

    function testPrivacyV2_RevertWhenTokenBridgeType3PrivacySettlementUnsupported() public {
        _configureTokenBridgeType3(true, false);

        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.mode = IPaymentKitaGateway.PaymentMode.PRIVACY;

        IPaymentKitaGateway.PrivateRouting memory privacy;
        privacy.intentId = keccak256("intent-token-bridge-privacy-capability-missing");
        privacy.stealthReceiver = _deployStealthEscrow();

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        vm.expectRevert(PaymentKitaGateway.TokenBridgePrivacySettlementUnsupported.selector);
        gateway.createPaymentPrivate(req, privacy);
        vm.stopPrank();
    }

    function testPrivacyV2_TokenBridgeType3SucceedsWhenPrivacySettlementEnabled() public {
        _configureTokenBridgeType3(true, true);

        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.mode = IPaymentKitaGateway.PaymentMode.PRIVACY;
        req.bridgeOption = 3;

        IPaymentKitaGateway.PrivateRouting memory privacy;
        privacy.intentId = keccak256("intent-token-bridge-privacy-capability-enabled");
        privacy.stealthReceiver = _deployStealthEscrow();

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        bytes32 pid = gateway.createPaymentPrivate(req, privacy);
        vm.stopPrank();

        assertTrue(pid != bytes32(0));
        assertEq(gateway.paymentBridgeType(pid), 3);
        assertEq(gateway.privacyIntentByPayment(pid), privacy.intentId);
    }

    function testV2CreatePayment_FuzzAmountBridgeTokenPath(uint96 amount) public {
        vm.assume(amount > 1e6);
        uint256 amt = uint256(amount);

        IPaymentKitaGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.amountInSource = amt;
        req.minBridgeAmountOut = 0;

        bridgeToken.mint(user, amt + 1e18);
        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        bytes32 pid = gateway.createPayment(req);
        vm.stopPrank();

        assertTrue(pid != bytes32(0));
    }
}
