// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../src/PayChainGateway.sol";
import "../src/PayChainRouter.sol";
import "../src/vaults/PayChainVault.sol";
import "../src/TokenRegistry.sol";
import "../src/interfaces/IPayChainGateway.sol";
import "../src/interfaces/IBridgeAdapter.sol";
import "../src/interfaces/ISwapper.sol";

contract MockTokenInvariant is ERC20 {
    constructor(string memory n, string memory s) ERC20(n, s) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockNoopAdapterInvariant is IBridgeAdapter {
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

contract MockInvariantSwapper is ISwapper {
    using SafeERC20 for IERC20;

    PayChainVault public immutable vault;
    mapping(bytes32 => bool) public routeExists;
    mapping(bytes32 => bool) public routeIsDirect;
    mapping(bytes32 => uint256) public routeRateWad;

    constructor(address _vault) {
        vault = PayChainVault(_vault);
    }

    function setRoute(address tokenIn, address tokenOut, bool exists, bool isDirect, uint256 rateWad) external {
        bytes32 k = keccak256(abi.encodePacked(tokenIn, tokenOut));
        routeExists[k] = exists;
        routeIsDirect[k] = isDirect;
        routeRateWad[k] = rateWad;
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
        require(amountOut >= minAmountOut, "slippage");
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
        require(amountOut >= minAmountOut, "slippage");
        IERC20(tokenOut).safeTransfer(recipient, amountOut);
    }

    function getQuote(address tokenIn, address tokenOut, uint256 amountIn) public view returns (uint256 amountOut) {
        bytes32 k = keccak256(abi.encodePacked(tokenIn, tokenOut));
        require(routeExists[k], "NoRoute");
        uint256 r = routeRateWad[k] == 0 ? 1e18 : routeRateWad[k];
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

contract PayChainGatewayV2Handler is Test {
    PayChainGateway public gateway;
    PayChainRouter public router;
    PayChainVault public vault;
    MockTokenInvariant public sourceToken;
    MockTokenInvariant public bridgeToken;
    MockTokenInvariant public destToken;

    string public constant DEST = "eip155:137";
    address[] public actors;

    bytes32[] private _createdPaymentIds;
    mapping(bytes32 => bool) public privatePayment;

    constructor(
        PayChainGateway _gateway,
        PayChainRouter _router,
        PayChainVault _vault,
        MockTokenInvariant _sourceToken,
        MockTokenInvariant _bridgeToken,
        MockTokenInvariant _destToken
    ) {
        gateway = _gateway;
        router = _router;
        vault = _vault;
        sourceToken = _sourceToken;
        bridgeToken = _bridgeToken;
        destToken = _destToken;

        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCAFE));
        actors.push(address(0xD00D));
    }

    function createdCount() external view returns (uint256) {
        return _createdPaymentIds.length;
    }

    function createdAt(uint256 i) external view returns (bytes32) {
        return _createdPaymentIds[i];
    }

    function actCreateV2(
        uint256 actorSeed,
        uint256 amountSeed,
        bool useSourceToken,
        bool explicitBridgeToken,
        uint8 bridgeOptionSeed
    ) external {
        address actor = actors[actorSeed % actors.length];
        uint256 amount = bound(amountSeed, 1e6, 1_000_000e18);
        address src = useSourceToken ? address(sourceToken) : address(bridgeToken);
        uint8 option = bridgeOptionSeed % 4;
        if (option == 3) {
            option = 255;
        }

        IPayChainGateway.PaymentRequestV2 memory req;
        req.destChainIdBytes = bytes(DEST);
        req.receiverBytes = abi.encode(address(uint160(uint256(keccak256(abi.encode(actor, amount))))));
        req.sourceToken = src;
        req.bridgeTokenSource = explicitBridgeToken ? address(bridgeToken) : address(0);
        req.destToken = address(destToken);
        req.amountInSource = amount;
        req.minBridgeAmountOut = 0;
        req.minDestAmountOut = 0;
        req.mode = IPayChainGateway.PaymentMode.REGULAR;
        req.bridgeOption = option;

        MockTokenInvariant(src).mint(actor, amount + 1e18);
        vm.deal(actor, 5 ether);
        vm.startPrank(actor);
        MockTokenInvariant(src).approve(address(vault), type(uint256).max);
        (, , uint256 requiredNativeFee) = gateway.previewApprovalV2(req);
        (bool ok, bytes memory out) = address(gateway).call{value: requiredNativeFee}(
            abi.encodeWithSelector(IPayChainGateway.createPaymentV2.selector, req)
        );
        vm.stopPrank();

        if (!ok) {
            return;
        }
        if (_createdPaymentIds.length >= 128) {
            return;
        }
        bytes32 paymentId = abi.decode(out, (bytes32));
        _createdPaymentIds.push(paymentId);
    }

    function actCreatePrivateV2(
        uint256 actorSeed,
        uint256 amountSeed,
        bool useSourceToken,
        bool explicitBridgeToken
    ) external {
        address actor = actors[actorSeed % actors.length];
        uint256 amount = bound(amountSeed, 1e6, 1_000_000e18);
        address src = useSourceToken ? address(sourceToken) : address(bridgeToken);

        IPayChainGateway.PaymentRequestV2 memory req;
        req.destChainIdBytes = bytes(DEST);
        req.receiverBytes = abi.encode(address(uint160(uint256(keccak256(abi.encode(actor, amount, "r"))))));
        req.sourceToken = src;
        req.bridgeTokenSource = explicitBridgeToken ? address(bridgeToken) : address(0);
        req.destToken = address(destToken);
        req.amountInSource = amount;
        req.minBridgeAmountOut = 0;
        req.minDestAmountOut = 0;
        req.mode = IPayChainGateway.PaymentMode.PRIVACY;
        req.bridgeOption = 255;

        IPayChainGateway.PrivateRouting memory privacy;
        privacy.intentId = keccak256(abi.encode(actor, amount, block.number));
        privacy.stealthReceiver = address(uint160(uint256(keccak256(abi.encode(actor, amount, "s")))));

        MockTokenInvariant(src).mint(actor, amount + 1e18);
        vm.deal(actor, 5 ether);
        vm.startPrank(actor);
        MockTokenInvariant(src).approve(address(vault), type(uint256).max);
        (, , uint256 requiredNativeFee) = gateway.previewApprovalV2(req);
        (bool ok, bytes memory out) = address(gateway).call{value: requiredNativeFee}(
            abi.encodeWithSelector(IPayChainGateway.createPaymentPrivateV2.selector, req, privacy)
        );
        vm.stopPrank();

        if (!ok) {
            return;
        }
        if (_createdPaymentIds.length >= 128) {
            return;
        }
        bytes32 paymentId = abi.decode(out, (bytes32));
        _createdPaymentIds.push(paymentId);
        privatePayment[paymentId] = true;
    }
}

contract PayChainGatewayV2InvariantTest is StdInvariant, Test {
    PayChainGateway gateway;
    PayChainRouter router;
    PayChainVault vault;
    TokenRegistry registry;
    MockNoopAdapterInvariant adapter;
    MockInvariantSwapper swapper;
    MockTokenInvariant sourceToken;
    MockTokenInvariant bridgeToken;
    MockTokenInvariant destToken;
    PayChainGatewayV2Handler handler;

    string constant DEST = "eip155:137";

    function setUp() public {
        sourceToken = new MockTokenInvariant("Source", "SRC");
        bridgeToken = new MockTokenInvariant("Bridge", "BRG");
        destToken = new MockTokenInvariant("Dest", "DST");

        registry = new TokenRegistry();
        vault = new PayChainVault();
        router = new PayChainRouter();
        gateway = new PayChainGateway(address(vault), address(router), address(registry), address(this));
        adapter = new MockNoopAdapterInvariant();
        swapper = new MockInvariantSwapper(address(vault));

        registry.setTokenSupport(address(sourceToken), true);
        registry.setTokenSupport(address(bridgeToken), true);
        registry.setTokenSupport(address(destToken), true);

        router.registerAdapter(DEST, 1, address(adapter));
        gateway.setDefaultBridgeType(DEST, 1);

        vault.setAuthorizedSpender(address(gateway), true);
        vault.setAuthorizedSpender(address(adapter), true);
        vault.setAuthorizedSpender(address(swapper), true);

        gateway.setSwapper(address(swapper));
        gateway.setEnableSourceSideSwap(true);
        gateway.setBridgeTokenForDest(DEST, address(bridgeToken));

        swapper.setRoute(address(sourceToken), address(bridgeToken), true, false, 1e18);
        bridgeToken.mint(address(swapper), 10_000_000e18);

        handler = new PayChainGatewayV2Handler(gateway, router, vault, sourceToken, bridgeToken, destToken);
        targetContract(address(handler));
    }

    function invariant_V2CreatedCountBounded() external {
        assertTrue(handler.createdCount() <= 128, "created payment list exceeded bound");
    }

    function invariant_V2PaymentStateIsConsistent() external {
        uint256 n = handler.createdCount();
        if (n == 0) return;

        uint256 i = uint256(keccak256(abi.encodePacked(block.number, block.prevrandao))) % n;
        bytes32 paymentId = handler.createdAt(i);
        bytes32 bridgeMessageId = gateway.paymentToBridgeMessage(paymentId);
        assertTrue(bridgeMessageId != bytes32(0), "bridgeMessageId missing");
        assertEq(gateway.bridgeMessageToPayment(bridgeMessageId), paymentId, "reverse mapping mismatch");

        (
            address sender,
            address receiver,
            ,
            ,
            ,
            ,
            uint256 amount,
            ,
            IPayChainGateway.PaymentStatus status,
            uint256 createdAt
        ) = gateway.payments(paymentId);
        assertTrue(sender != address(0), "missing payment sender");
        assertTrue(receiver != address(0), "missing payment receiver");
        assertTrue(amount > 0, "payment amount zero");
        assertEq(uint256(status), uint256(IPayChainGateway.PaymentStatus.Processing), "unexpected status");
        assertTrue(createdAt > 0, "createdAt missing");

        (
            bytes32 msgPaymentId,
            address msgReceiver,
            ,
            ,
            uint256 msgAmount,
            string memory destChainId,
            ,
            address msgPayer
        ) = gateway.paymentMessages(paymentId);
        assertEq(msgPaymentId, paymentId, "message paymentId mismatch");
        assertEq(msgAmount, amount, "message amount mismatch");
        assertEq(keccak256(bytes(destChainId)), keccak256(bytes(DEST)), "dest chain mismatch");
        assertEq(msgPayer, sender, "bridge payer mismatch");

        uint8 bridgeType = gateway.paymentBridgeType(paymentId);
        assertTrue(bridgeType <= 2, "invalid bridge type");
        assertTrue(router.hasAdapter(DEST, bridgeType), "bridge adapter missing");

        if (handler.privatePayment(paymentId)) {
            address stealth = gateway.privacyStealthByPayment(paymentId);
            bytes32 intent = gateway.privacyIntentByPayment(paymentId);
            assertTrue(stealth != address(0), "stealth missing");
            assertTrue(intent != bytes32(0), "intent missing");
            assertEq(receiver, stealth, "payment receiver != stealth");
            assertEq(msgReceiver, stealth, "bridge msg receiver != stealth");
        }
    }
}
