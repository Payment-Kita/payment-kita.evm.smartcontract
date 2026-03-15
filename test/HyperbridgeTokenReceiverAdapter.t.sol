// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ITokenGateway, TeleportParams, TokenGatewayParams} from "@hyperbridge/core/apps/TokenGateway.sol";
import "../src/integrations/hyperbridge/HyperbridgeTokenReceiverAdapter.sol";
import "../src/vaults/PaymentKitaVault.sol";

interface ITokenGatewayReceiverEntry {
    function onTokenGatewayPayload(bytes calldata payload) external;
}

contract MockReceiverToken is ERC20 {
    constructor(string memory n, string memory s) ERC20(n, s) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockGatewayForReceiver {
    mapping(bytes32 => address) public privacyStealthByPayment;

    bytes32 public lastFinalizePaymentId;
    address public lastFinalizeReceiver;
    address public lastFinalizeToken;
    uint256 public lastFinalizeAmount;
    uint256 public finalizeIncomingCount;

    uint256 public finalizePrivacyCount;
    uint256 public reportPrivacyFailureCount;
    bool public revertFinalizePrivacyForward;
    bytes32 public registeredPaymentId;
    bytes32 public registeredIntentId;
    address public registeredStealthReceiver;
    address public registeredFinalReceiver;
    address public registeredSourceSender;
    uint256 public registerIncomingPrivacyContextCount;

    function setStealth(bytes32 paymentId, address stealthReceiver) external {
        privacyStealthByPayment[paymentId] = stealthReceiver;
    }

    function setRevertFinalizePrivacyForward(bool shouldRevert) external {
        revertFinalizePrivacyForward = shouldRevert;
    }

    function registerIncomingPrivacyContext(
        bytes32 paymentId,
        bytes32 intentId,
        address stealthReceiver,
        address finalReceiver,
        address sourceSender
    ) external {
        privacyStealthByPayment[paymentId] = stealthReceiver;
        registeredPaymentId = paymentId;
        registeredIntentId = intentId;
        registeredStealthReceiver = stealthReceiver;
        registeredFinalReceiver = finalReceiver;
        registeredSourceSender = sourceSender;
        registerIncomingPrivacyContextCount += 1;
    }

    function finalizeIncomingPayment(bytes32 paymentId, address receiver, address token, uint256 amount) external {
        lastFinalizePaymentId = paymentId;
        lastFinalizeReceiver = receiver;
        lastFinalizeToken = token;
        lastFinalizeAmount = amount;
        finalizeIncomingCount += 1;
    }

    function finalizePrivacyForward(bytes32, address, uint256) external {
        finalizePrivacyCount += 1;
        if (revertFinalizePrivacyForward) {
            revert("FORCED_PRIVACY_FORWARD_FAIL");
        }
    }

    function reportPrivacyForwardFailure(bytes32, string calldata) external {
        reportPrivacyFailureCount += 1;
    }
}

contract MockSwapperForReceiver {
    address public expectedTokenIn;
    address public expectedTokenOut;
    uint256 public expectedAmountIn;
    uint256 public expectedMinAmountOut;
    address public expectedRecipient;
    uint256 public amountOutToReturn;

    function setAmountOutToReturn(uint256 amountOut) external {
        amountOutToReturn = amountOut;
    }

    function swapFromVault(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut) {
        expectedTokenIn = tokenIn;
        expectedTokenOut = tokenOut;
        expectedAmountIn = amountIn;
        expectedMinAmountOut = minAmountOut;
        expectedRecipient = recipient;

        amountOut = amountOutToReturn;
        bool ok = ERC20(tokenOut).transfer(recipient, amountOut);
        require(ok, "dest transfer failed");
    }
}

contract MockTokenGatewayForReceiver is ITokenGateway {
    mapping(bytes32 => address) public erc20Map;
    mapping(bytes32 => address) public erc6160Map;
    mapping(bytes32 => address) public instanceMap;

    function setErc20(bytes32 assetId, address token) external {
        erc20Map[assetId] = token;
    }

    function params() external pure override returns (TokenGatewayParams memory) {
        return TokenGatewayParams({host: address(0x1001), dispatcher: address(0x1002)});
    }

    function erc20(bytes32 assetId) external view override returns (address) {
        return erc20Map[assetId];
    }

    function erc6160(bytes32 assetId) external view override returns (address) {
        return erc6160Map[assetId];
    }

    function instance(bytes calldata destination) external view override returns (address) {
        return instanceMap[keccak256(destination)];
    }

    function teleport(TeleportParams calldata) external payable override {
        revert("NOT_IMPLEMENTED");
    }

    function invokePayload(address adapter, bytes calldata payload) external {
        ITokenGatewayReceiverEntry(adapter).onTokenGatewayPayload(payload);
    }

    function invokePayloadWithTokenTransfer(
        address adapter,
        address token,
        uint256 amount,
        bytes calldata payload
    ) external {
        bool ok = ERC20(token).transfer(adapter, amount);
        require(ok, "bridge transfer failed");
        ITokenGatewayReceiverEntry(adapter).onTokenGatewayPayload(payload);
    }
}

contract HyperbridgeTokenReceiverAdapterTest is Test {
    uint8 constant PAYLOAD_VERSION_V1 = 1;
    uint8 constant PAYLOAD_VERSION_V2 = 2;
    bytes32 constant ASSET_ID = keccak256("USDC");

    MockReceiverToken bridgedToken;
    MockReceiverToken destToken;
    MockGatewayForReceiver gateway;
    PaymentKitaVault vault;
    MockSwapperForReceiver swapper;
    MockTokenGatewayForReceiver tokenGateway;
    HyperbridgeTokenReceiverAdapter adapter;

    address receiver = address(0xA11CE);
    bytes32 paymentId = keccak256("hb-token-receiver-payment");

    function setUp() public {
        bridgedToken = new MockReceiverToken("Bridged", "BRDG");
        destToken = new MockReceiverToken("Destination", "DST");
        gateway = new MockGatewayForReceiver();
        vault = new PaymentKitaVault();
        swapper = new MockSwapperForReceiver();
        tokenGateway = new MockTokenGatewayForReceiver();

        adapter = new HyperbridgeTokenReceiverAdapter(address(tokenGateway), address(gateway), address(vault));
        adapter.setSwapper(address(swapper));

        tokenGateway.setErc20(ASSET_ID, address(bridgedToken));

        bridgedToken.mint(address(tokenGateway), 1_000_000e6);
        destToken.mint(address(swapper), 1_000_000e6);
    }

    function _payload(
        uint8 version,
        bytes32 _paymentId,
        address _receiver,
        address _destToken,
        uint256 _minAmountOut,
        bytes32 _assetId,
        uint256 _bridgedAmount
    ) internal pure returns (bytes memory) {
        return abi.encode(version, _paymentId, _receiver, _destToken, _minAmountOut, _assetId, _bridgedAmount);
    }

    function _payloadV2Privacy(
        bytes32 _paymentId,
        address _receiver,
        address _destToken,
        uint256 _minAmountOut,
        bytes32 _assetId,
        uint256 _bridgedAmount,
        bytes32 _intentId,
        address _finalReceiver,
        address _sourceSender
    ) internal pure returns (bytes memory) {
        return abi.encode(
            PAYLOAD_VERSION_V2,
            _paymentId,
            _receiver,
            _destToken,
            _minAmountOut,
            _assetId,
            _bridgedAmount,
            true,
            _intentId,
            _receiver,
            _finalReceiver,
            _sourceSender
        );
    }

    function testOnTokenGatewayPayloadRevertsWhenCallerNotTokenGateway() public {
        bytes memory payload = _payload(PAYLOAD_VERSION_V1, paymentId, receiver, address(bridgedToken), 0, ASSET_ID, 100e6);

        vm.expectRevert(HyperbridgeTokenReceiverAdapter.NotTokenGateway.selector);
        adapter.onTokenGatewayPayload(payload);
    }

    function testOnTokenGatewayPayloadRevertsWhenVersionInvalid() public {
        bytes memory payload = _payload(9, paymentId, receiver, address(bridgedToken), 0, ASSET_ID, 100e6);

        vm.expectRevert(abi.encodeWithSelector(HyperbridgeTokenReceiverAdapter.UnsupportedPayloadVersion.selector, uint8(9)));
        tokenGateway.invokePayload(address(adapter), payload);
    }

    function testOnTokenGatewayPayloadRevertsWhenAssetUnknown() public {
        bytes32 unknownAsset = keccak256("UNKNOWN");
        bytes memory payload = _payload(PAYLOAD_VERSION_V1, paymentId, receiver, address(bridgedToken), 0, unknownAsset, 100e6);

        vm.expectRevert(abi.encodeWithSelector(HyperbridgeTokenReceiverAdapter.UnknownAsset.selector, unknownAsset));
        tokenGateway.invokePayload(address(adapter), payload);
    }

    function testOnTokenGatewayPayloadDirectSettlementFinalizesPayment() public {
        uint256 bridgedAmount = 250e6;
        bytes memory payload = _payload(
            PAYLOAD_VERSION_V1,
            paymentId,
            receiver,
            address(bridgedToken),
            0,
            ASSET_ID,
            bridgedAmount
        );

        tokenGateway.invokePayloadWithTokenTransfer(address(adapter), address(bridgedToken), bridgedAmount, payload);

        assertEq(bridgedToken.balanceOf(receiver), bridgedAmount);
        assertEq(gateway.finalizeIncomingCount(), 1);
        assertEq(gateway.lastFinalizePaymentId(), paymentId);
        assertEq(gateway.lastFinalizeReceiver(), receiver);
        assertEq(gateway.lastFinalizeToken(), address(bridgedToken));
        assertEq(gateway.lastFinalizeAmount(), bridgedAmount);
    }

    function testOnTokenGatewayPayloadSwapSettlementFinalizesPayment() public {
        uint256 bridgedAmount = 300e6;
        uint256 settledAmount = 270e6;
        swapper.setAmountOutToReturn(settledAmount);

        bytes memory payload = _payload(PAYLOAD_VERSION_V1, paymentId, receiver, address(destToken), 123, ASSET_ID, bridgedAmount);
        tokenGateway.invokePayloadWithTokenTransfer(address(adapter), address(bridgedToken), bridgedAmount, payload);

        assertEq(bridgedToken.balanceOf(address(vault)), bridgedAmount);
        assertEq(destToken.balanceOf(receiver), settledAmount);
        assertEq(gateway.lastFinalizeToken(), address(destToken));
        assertEq(gateway.lastFinalizeAmount(), settledAmount);

        assertEq(swapper.expectedTokenIn(), address(bridgedToken));
        assertEq(swapper.expectedTokenOut(), address(destToken));
        assertEq(swapper.expectedAmountIn(), bridgedAmount);
        assertEq(swapper.expectedMinAmountOut(), 123);
        assertEq(swapper.expectedRecipient(), receiver);
    }

    function testOnTokenGatewayPayloadBlocksReplay() public {
        uint256 bridgedAmount = 111e6;
        bytes memory payload = _payload(
            PAYLOAD_VERSION_V1,
            paymentId,
            receiver,
            address(bridgedToken),
            0,
            ASSET_ID,
            bridgedAmount
        );

        tokenGateway.invokePayloadWithTokenTransfer(address(adapter), address(bridgedToken), bridgedAmount, payload);

        bytes32 payloadHash = keccak256(payload);
        vm.expectRevert(
            abi.encodeWithSelector(HyperbridgeTokenReceiverAdapter.SettlementAlreadyProcessed.selector, payloadHash)
        );
        tokenGateway.invokePayloadWithTokenTransfer(address(adapter), address(bridgedToken), bridgedAmount, payload);
    }

    function testOnTokenGatewayPayloadPrivacyFailureIsReported() public {
        uint256 bridgedAmount = 100e6;
        gateway.setStealth(paymentId, receiver);
        gateway.setRevertFinalizePrivacyForward(true);

        bytes memory payload = _payload(
            PAYLOAD_VERSION_V1,
            paymentId,
            receiver,
            address(bridgedToken),
            0,
            ASSET_ID,
            bridgedAmount
        );
        tokenGateway.invokePayloadWithTokenTransfer(address(adapter), address(bridgedToken), bridgedAmount, payload);

        assertEq(gateway.finalizeIncomingCount(), 1);
        assertEq(gateway.finalizePrivacyCount(), 0);
        assertEq(gateway.reportPrivacyFailureCount(), 1);
    }

    function testOnTokenGatewayPayloadV2PrivacyRegistersContextAndForwards() public {
        uint256 bridgedAmount = 77e6;
        bytes32 intentId = keccak256("intent-v2");
        address finalReceiver = address(0xBADA55);
        address sourceSender = address(0xCAFE);
        bytes memory payload = _payloadV2Privacy(
            paymentId,
            receiver,
            address(bridgedToken),
            0,
            ASSET_ID,
            bridgedAmount,
            intentId,
            finalReceiver,
            sourceSender
        );

        tokenGateway.invokePayloadWithTokenTransfer(address(adapter), address(bridgedToken), bridgedAmount, payload);

        assertEq(gateway.registerIncomingPrivacyContextCount(), 1);
        assertEq(gateway.registeredPaymentId(), paymentId);
        assertEq(gateway.registeredIntentId(), intentId);
        assertEq(gateway.registeredStealthReceiver(), receiver);
        assertEq(gateway.registeredFinalReceiver(), finalReceiver);
        assertEq(gateway.registeredSourceSender(), sourceSender);
        assertEq(gateway.finalizeIncomingCount(), 1);
        assertEq(gateway.finalizePrivacyCount(), 1);
        assertEq(gateway.reportPrivacyFailureCount(), 0);
    }
}
