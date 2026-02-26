// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../src/PayChainGateway.sol";
import "../src/PayChainRouter.sol";
import "../src/vaults/PayChainVault.sol";
import "../src/TokenRegistry.sol";
import "../src/interfaces/IPayChainGateway.sol";
import "../src/interfaces/IBridgeAdapter.sol";
import "../src/interfaces/ISwapper.sol";

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

contract MockV2Swapper is ISwapper {
    using SafeERC20 for IERC20;

    PayChainVault public immutable vault;
    mapping(bytes32 => bool) public routeExists;
    mapping(bytes32 => bool) public routeIsDirect;
    mapping(bytes32 => uint256) public routeRateWad;
    mapping(bytes32 => bool) public forceQuoteFail;

    constructor(address _vault) {
        vault = PayChainVault(_vault);
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

contract PayChainGatewayV2Phase1Test is Test {
    PayChainGateway gateway;
    PayChainRouter router;
    PayChainVault vault;
    TokenRegistry registry;
    MockNoopAdapterV2 adapter;
    MockFeeAdapterV2 feeAdapter;
    MockV2Swapper swapper;
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
        vault = new PayChainVault();
        router = new PayChainRouter();
        gateway = new PayChainGateway(address(vault), address(router), address(registry), address(this));
        adapter = new MockNoopAdapterV2();
        feeAdapter = new MockFeeAdapterV2();
        swapper = new MockV2Swapper(address(vault));

        registry.setTokenSupport(address(sourceToken), true);
        registry.setTokenSupport(address(bridgeToken), true);
        registry.setTokenSupport(address(destToken), true);

        router.registerAdapter(DEST, 1, address(adapter));
        gateway.setDefaultBridgeType(DEST, 1);
        router.registerAdapter(DEST_2, 1, address(adapter));
        gateway.setDefaultBridgeType(DEST_2, 1);
        router.registerAdapter("eip155:10", 1, address(feeAdapter));
        gateway.setDefaultBridgeType("eip155:10", 1);

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
    ) internal view returns (IPayChainGateway.PaymentRequestV2 memory req) {
        req.destChainIdBytes = bytes(DEST);
        req.receiverBytes = abi.encode(receiver);
        req.sourceToken = src;
        req.bridgeTokenSource = bridgeSrc;
        req.destToken = dst;
        req.amountInSource = 100e18;
        req.minBridgeAmountOut = 90e18;
        req.minDestAmountOut = 0;
        req.mode = IPayChainGateway.PaymentMode.REGULAR;
        req.bridgeOption = 255;
    }

    function testV2CreatePayment_NormalizesSourceToBridgeToken() public {
        swapper.setRoute(address(sourceToken), address(bridgeToken), true, false, 1e18);

        IPayChainGateway.PaymentRequestV2 memory req = _baseReq(address(sourceToken), address(0), address(destToken));
        vm.startPrank(user);
        sourceToken.approve(address(vault), type(uint256).max);
        bytes32 pid = gateway.createPaymentV2(req);
        vm.stopPrank();

        (
            bytes32 storedPaymentId,
            ,
            address storedSourceToken,
            ,
            uint256 storedAmount,
            ,
            ,
        ) = gateway.paymentMessages(pid);
        assertEq(storedPaymentId, pid);
        assertEq(storedSourceToken, address(bridgeToken));
        assertEq(storedAmount, 100e18);
    }

    function testV2QuotePaymentCost_NoRouteToBridgeToken() public {
        // no swapper route configured
        IPayChainGateway.PaymentRequestV2 memory req = _baseReq(address(sourceToken), address(0), address(destToken));

        (, , , , bool bridgeQuoteOk, string memory bridgeQuoteReason) = gateway.quotePaymentCostV2(req);
        assertFalse(bridgeQuoteOk);
        assertEq(bridgeQuoteReason, "no_route_to_bridge_token");
    }

    function testV2CreatePayment_RevertBridgeTokenNotConfigured() public {
        IPayChainGateway.PaymentRequestV2 memory req = _baseReq(address(sourceToken), address(0), address(destToken));
        req.destChainIdBytes = bytes(DEST_2); // has adapter/default bridge but no lane bridge token mapping

        vm.startPrank(user);
        sourceToken.approve(address(vault), type(uint256).max);
        vm.expectRevert(bytes("Bridge token not configured"));
        gateway.createPaymentV2(req);
        vm.stopPrank();
    }

    function testV1CreatePayment_RevertWhenLaneDisabled() public {
        gateway.setV1LaneDisabled(DEST, true);

        vm.startPrank(user);
        sourceToken.approve(address(vault), type(uint256).max);
        vm.expectRevert(bytes("V1 disabled for destination"));
        gateway.createPayment(bytes(DEST), abi.encode(receiver), address(sourceToken), address(sourceToken), 100e18);
        vm.stopPrank();
    }

    function testV1CreatePayment_RevertWhenGlobalDisabled() public {
        gateway.setV1GlobalDisabled(true);

        vm.startPrank(user);
        sourceToken.approve(address(vault), type(uint256).max);
        vm.expectRevert(bytes("V1 globally disabled"));
        gateway.createPayment(bytes(DEST), abi.encode(receiver), address(sourceToken), address(sourceToken), 100e18);
        vm.stopPrank();
    }

    function testV2CreatePayment_StillWorksWhenV1Disabled() public {
        gateway.setV1LaneDisabled(DEST, true);

        IPayChainGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        bytes32 pid = gateway.createPaymentV2(req);
        vm.stopPrank();

        assertTrue(pid != bytes32(0));
    }

    function testPrivacyCrossChainV2_StealthReceiverAndIntentStored() public {
        IPayChainGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.mode = IPayChainGateway.PaymentMode.PRIVACY;

        IPayChainGateway.PrivateRouting memory privacy;
        privacy.intentId = keccak256("intent-1");
        privacy.stealthReceiver = address(0xABCD);

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        bytes32 pid = gateway.createPaymentPrivateV2(req, privacy);
        vm.stopPrank();

        (, address storedReceiver,,,,,,,,) = gateway.payments(pid);
        assertEq(storedReceiver, privacy.stealthReceiver);
        assertEq(gateway.privacyIntentByPayment(pid), privacy.intentId);
        assertEq(gateway.privacyStealthByPayment(pid), privacy.stealthReceiver);

        (
            bytes32 storedPaymentId,
            address msgReceiver,
            ,
            ,
            ,
            ,
            ,
        ) = gateway.paymentMessages(pid);
        assertEq(storedPaymentId, pid);
        assertEq(msgReceiver, privacy.stealthReceiver);
    }

    function testV2CreatePayment_RevertInvalidBridgeOption() public {
        IPayChainGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.bridgeOption = 9;

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        vm.expectRevert();
        gateway.createPaymentV2(req);
        vm.stopPrank();
    }

    function testV2CreatePayment_RevertWhenSourceSideSwapDisabled() public {
        gateway.setEnableSourceSideSwap(false);
        swapper.setRoute(address(sourceToken), address(bridgeToken), true, false, 1e18);

        IPayChainGateway.PaymentRequestV2 memory req = _baseReq(address(sourceToken), address(0), address(destToken));
        vm.startPrank(user);
        sourceToken.approve(address(vault), type(uint256).max);
        vm.expectRevert(bytes("Source-side swap disabled"));
        gateway.createPaymentV2(req);
        vm.stopPrank();
    }

    function testV2CreatePayment_RevertWhenNoRouteToBridgeToken() public {
        // source -> bridge route intentionally not configured
        IPayChainGateway.PaymentRequestV2 memory req = _baseReq(address(sourceToken), address(0), address(destToken));

        vm.startPrank(user);
        sourceToken.approve(address(vault), type(uint256).max);
        vm.expectRevert(bytes("No route to bridge token"));
        gateway.createPaymentV2(req);
        vm.stopPrank();
    }

    function testV2CreatePayment_RevertInsufficientNativeFeeAfterQuote() public {
        // route that does not require source swap to isolate fee failure
        gateway.setBridgeTokenForDest("eip155:10", address(bridgeToken));
        feeAdapter.setQuotedFee(1e15);

        IPayChainGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.destChainIdBytes = bytes("eip155:10");

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        vm.expectRevert(bytes("Insufficient native fee"));
        gateway.createPaymentV2(req);
        vm.stopPrank();
    }

    function testV2CreatePaymentDefaultBridge_IgnoresReqBridgeOptionAndUsesDefault() public {
        IPayChainGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.bridgeOption = 2; // LZ, but wrapper should force DEFAULT.

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        bytes32 pid = gateway.createPaymentV2DefaultBridge(req);
        vm.stopPrank();

        assertTrue(pid != bytes32(0));
        assertEq(gateway.paymentBridgeType(pid), gateway.defaultBridgeTypes(DEST));
    }

    function testV2QuotePaymentCost_ReasonSourceSideSwapDisabled() public {
        gateway.setEnableSourceSideSwap(false);
        IPayChainGateway.PaymentRequestV2 memory req = _baseReq(address(sourceToken), address(0), address(destToken));

        (, , , uint8 bridgeType, bool bridgeQuoteOk, string memory reason) = gateway.quotePaymentCostV2(req);
        assertEq(bridgeType, 1);
        assertFalse(bridgeQuoteOk);
        assertEq(reason, "source_side_swap_disabled");
    }

    function testV2QuotePaymentCost_ReasonSwapperNotConfigured() public {
        gateway.setSwapper(address(0));
        IPayChainGateway.PaymentRequestV2 memory req = _baseReq(address(sourceToken), address(0), address(destToken));

        (, , , uint8 bridgeType, bool bridgeQuoteOk, string memory reason) = gateway.quotePaymentCostV2(req);
        assertEq(bridgeType, 1);
        assertFalse(bridgeQuoteOk);
        assertEq(reason, "swapper_not_configured");
    }

    function testV2QuotePaymentCost_ReasonSourceSwapQuoteFailed() public {
        swapper.setRoute(address(sourceToken), address(bridgeToken), true, false, 1e18);
        swapper.setForceQuoteFail(address(sourceToken), address(bridgeToken), true);
        IPayChainGateway.PaymentRequestV2 memory req = _baseReq(address(sourceToken), address(0), address(destToken));

        (, , , uint8 bridgeType, bool bridgeQuoteOk, string memory reason) = gateway.quotePaymentCostV2(req);
        assertEq(bridgeType, 1);
        assertFalse(bridgeQuoteOk);
        assertEq(reason, "source_swap_quote_failed");
    }

    function testPreviewApprovalV2_AppliesNativeFeeBuffer() public {
        gateway.setBridgeTokenForDest("eip155:10", address(bridgeToken));
        feeAdapter.setQuotedFee(1e15); // 0.001 native

        IPayChainGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.destChainIdBytes = bytes("eip155:10");

        (uint256 platformFee,,,,,) = gateway.quotePaymentCostV2(req);
        (address approvalToken, uint256 approvalAmount, uint256 requiredNativeFee) = gateway.previewApprovalV2(req);

        assertEq(approvalToken, address(bridgeToken));
        assertEq(approvalAmount, req.amountInSource + platformFee);
        // default buffer = 500 bps => +5%
        assertEq(requiredNativeFee, 1_050_000_000_000_000);
    }

    function testV2CreatePayment_RevertBridgeOptionRouteMissing() public {
        // Explicit LayerZero option (2) has no registered adapter in setup.
        IPayChainGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.bridgeOption = 2;

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                PayChainGateway.BridgeRouteNotConfigured.selector,
                DEST,
                uint8(2)
            )
        );
        gateway.createPaymentV2(req);
        vm.stopPrank();
    }

    function testPrivacyV2_RevertWhenIntentMissing() public {
        IPayChainGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.mode = IPayChainGateway.PaymentMode.PRIVACY;

        IPayChainGateway.PrivateRouting memory privacy;
        privacy.intentId = bytes32(0);
        privacy.stealthReceiver = address(0xABCD);

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        vm.expectRevert(bytes("Missing privacy intent"));
        gateway.createPaymentPrivateV2(req, privacy);
        vm.stopPrank();
    }

    function testPrivacyV2_RevertWhenStealthReceiverZero() public {
        IPayChainGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.mode = IPayChainGateway.PaymentMode.PRIVACY;

        IPayChainGateway.PrivateRouting memory privacy;
        privacy.intentId = keccak256("intent-zero-stealth");
        privacy.stealthReceiver = address(0);

        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        vm.expectRevert(bytes("Invalid stealth receiver"));
        gateway.createPaymentPrivateV2(req, privacy);
        vm.stopPrank();
    }

    function testV2CreatePayment_FuzzAmountBridgeTokenPath(uint96 amount) public {
        vm.assume(amount > 1e6);
        uint256 amt = uint256(amount);

        IPayChainGateway.PaymentRequestV2 memory req = _baseReq(address(bridgeToken), address(0), address(destToken));
        req.amountInSource = amt;
        req.minBridgeAmountOut = 0;

        bridgeToken.mint(user, amt + 1e18);
        vm.startPrank(user);
        bridgeToken.approve(address(vault), type(uint256).max);
        bytes32 pid = gateway.createPaymentV2(req);
        vm.stopPrank();

        assertTrue(pid != bytes32(0));
        (, , , , uint256 storedAmount, , ,) = gateway.paymentMessages(pid);
        assertEq(storedAmount, amt);
    }
}
